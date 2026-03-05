defmodule MobaWeb.V2.MatchLive do
  use MobaWeb, :v2_live_view

  alias MobaWeb.V2.TutorialComponent

  embed_templates "match_live/*"

  @tick_timeout 500
  @max_tick 15

  def mount(%{"id" => match_id}, _session, socket) do
    socket = socket_init(match_id, @max_tick, socket)

    if connected?(socket) do
      MobaWeb.subscribe(socket.assigns.channel)
    end

    {:ok, socket}
  end

  def handle_event("hero-tab", %{"type" => tab}, socket) do
    {:noreply, assign(socket, hero_tab: tab)}
  end

  def handle_event("repeat", _, %{assigns: %{latest_match: match}} = socket) when not is_nil(match) do
    {:noreply, assign(socket, picked_heroes: match.player_picks)}
  end

  def handle_event("repeat", _, socket), do: {:noreply, socket}

  def handle_event("pick-hero", %{"id" => id}, %{assigns: %{picked_heroes: heroes}} = socket) do
    hero = Game.get_hero!(id)
    {:noreply, assign(socket, picked_heroes: heroes ++ [hero])}
  end

  def handle_event("unpick-hero", %{"id" => id}, %{assigns: %{picked_heroes: heroes}} = socket) do
    hero = Enum.find(heroes, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, picked_heroes: heroes -- [hero])}
  end

  def handle_event("pick-team", %{"id" => id}, %{assigns: %{teams: teams}} = socket) do
    team = Enum.find(teams, &(&1.id == String.to_integer(id)))
    Game.update_team!(team, %{used_count: team.used_count + 1})
    {:noreply, assign(socket, picked_heroes: Enum.take(team.picks, 5))}
  end

  def handle_event("move-up", %{"id" => id}, socket) do
    {:noreply, move(String.to_integer(id), -1, socket)}
  end

  def handle_event("move-down", %{"id" => id}, socket) do
    {:noreply, move(String.to_integer(id), 1, socket)}
  end

  def handle_event("start", _, %{assigns: %{match: match, picked_heroes: picked_heroes}} = socket) do
    ids = picked_heroes |> Enum.take(5) |> Enum.map(& &1.id)
    Task.Supervisor.async_nolink(Moba.TaskSupervisor, fn -> Game.continue_match!(match, ids) end)
    schedule_tick()
    {:noreply, assign(socket, tick: 0)}
  end

  def handle_event("finish-tutorial", _, socket) do
    {:noreply, TutorialComponent.finish_arena(socket)}
  end

  def handle_info({:tutorial, %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def handle_info(:tick, %{assigns: %{tick: tick, match: %{id: match_id, winner_id: winner_id}}} = socket)
      when is_nil(winner_id) and tick < @max_tick do
    schedule_tick()
    {:noreply, socket_init(match_id, tick + 1, socket)}
  end

  def handle_info(:tick, %{assigns: %{tick: tick, battles: battles}} = socket) when tick < length(battles) do
    schedule_tick()
    {:noreply, assign(socket, tick: tick + 1)}
  end

  def handle_info(:tick, socket), do: {:noreply, socket}

  def handle_info({:DOWN, _ref, _, _, _reason}, %{assigns: %{match: match}} = socket) do
    match = Game.reset_match!(match)
    {:noreply, socket_init(match.id, @max_tick, socket)}
  end

  def handle_info({ref, match}, socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket_init(match.id, socket.assigns.tick, socket)}
  end

  def render(assigns), do: show(assigns)

  defp socket_init(match_id, tick, %{assigns: %{current_player: player}} = socket) do
    match = Game.get_match!(match_id)
    latest_match = Game.latest_manual_match(player)
    battles = Engine.list_match_battles(match_id)
    teams = Game.list_teams(player)
    trained_heroes = Game.trained_pvp_heroes(player.id, [], 20)
    hero_tab = if length(teams) > 0, do: "teams", else: "trained"

    assign(socket,
      sidebar_code: "arena",
      channel: "match-#{match_id}",
      match: match,
      battles: battles,
      tick: tick,
      trained_heroes: trained_heroes,
      picked_heroes: Enum.filter(match.player_picks, & &1),
      generated_heroes: available_heroes(match, player, trained_heroes),
      tutorial_step: player.tutorial_step,
      hero_tab: hero_tab,
      latest_match: latest_match,
      teams: teams,
      hide_footer: true
    )
  end

  defp available_heroes(match, %{pvp_tier: 0}, _trained_heroes), do: match.generated_picks

  defp available_heroes(_match, _player, trained_heroes) do
    Moba.pve_ranking_available()
    |> Enum.reject(&Enum.member?(trained_heroes, &1))
    |> Enum.take(10)
  end

  defp move(hero_id, slide, %{assigns: %{picked_heroes: picked_heroes}} = socket) do
    index = Enum.find_index(picked_heroes, &(&1.id == hero_id))

    if is_nil(index) or index + slide < 0 or index + slide >= length(picked_heroes) do
      socket
    else
      assign(socket, picked_heroes: Enum.slide(picked_heroes, index, index + slide))
    end
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_timeout)

  defp player_pick(
         %{
           attacker_id: attacker_id,
           defender_id: defender_id,
           attacker_player_id: attacker_player_id,
           defender_player_id: defender_player_id
         },
         %{player_id: player_id, player_picks: picks}
       ) do
    Enum.find(
      picks,
      &((&1.id == attacker_id && attacker_player_id == player_id) ||
          (&1.id == defender_id && defender_player_id == player_id))
    )
  end

  defp opponent_pick(
         %{
           attacker_id: attacker_id,
           defender_id: defender_id,
           attacker_player_id: attacker_player_id,
           defender_player_id: defender_player_id
         },
         %{opponent_id: opponent_id, opponent_picks: picks}
       ) do
    Enum.find(
      picks,
      &((&1.id == attacker_id && attacker_player_id == opponent_id) ||
          (&1.id == defender_id && defender_player_id == opponent_id))
    )
  end

  defp turn_hero_for(battle, player) do
    turn = List.last(battle.turns)
    if turn.attacker.player_id == player.id, do: turn.attacker, else: turn.defender
  end
end
