defmodule MobaWeb.V2.MatchLive do
  use MobaWeb, :v2_live_view

  import MobaWeb.CoreComponents, only: [icon: 1]

  alias MobaWeb.V2.TutorialComponent

  embed_templates "match_live/*"

  @tick_timeout 500
  @max_tick 15

  def mount(%{"id" => match_id}, _session, socket) do
    socket = socket_init(match_id, @max_tick, socket) |> TutorialComponent.skip_arena()

    socket =
      attach_hook(socket, :authorize_match_changes, :handle_event, fn event, _, socket ->
        if event in ~w(repeat pick-hero unpick-hero pick-team move-up move-down start) do
          match = Game.get_match!(socket.assigns.match.id)

          if match.player_id == socket.assigns.current_player.id && is_nil(match.phase) && is_nil(match.winner_id),
            do: {:cont, assign(socket, match: match)},
            else: {:halt, socket}
        else
          {:cont, socket}
        end
      end)

    if connected?(socket) do
      MobaWeb.subscribe(socket.assigns.channel)
    end

    {:ok, socket}
  end

  def handle_event("hero-tab", %{"type" => tab}, socket) do
    {:noreply, assign(socket, hero_tab: tab)}
  end

  def handle_event("toggle-battle-details", _, socket) do
    {:noreply, assign(socket, show_battle_details: !socket.assigns.show_battle_details)}
  end

  def handle_event("repeat", _, %{assigns: %{latest_match: match}} = socket) when not is_nil(match) do
    ids = Enum.map(match.player_picks, & &1.id)

    if Moba.Game.Matches.valid_picks?(socket.assigns.match, socket.assigns.current_player, ids),
      do: {:noreply, assign(socket, picked_heroes: match.player_picks)},
      else: {:noreply, socket}
  end

  def handle_event("repeat", _, socket), do: {:noreply, socket}

  def handle_event("pick-hero", %{"id" => id}, %{assigns: %{picked_heroes: heroes}} = socket) do
    hero = Game.get_hero!(id)
    eligible = Moba.Game.Matches.selectable_heroes(socket.assigns.match, socket.assigns.current_player, [hero.id])

    if length(heroes) < 5 && !Enum.any?(heroes, &(&1.id == hero.id)) && eligible != [],
      do: {:noreply, assign(socket, picked_heroes: heroes ++ [hero])},
      else: {:noreply, socket}
  end

  def handle_event("unpick-hero", %{"id" => id}, %{assigns: %{picked_heroes: heroes}} = socket) do
    hero = Enum.find(heroes, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, picked_heroes: heroes -- [hero])}
  end

  def handle_event("pick-team", %{"id" => id}, %{assigns: %{teams: teams}} = socket) do
    team = Enum.find(teams, &(&1.id == String.to_integer(id)))
    picks = if team, do: Enum.take(team.picks, 5), else: []

    if Moba.Game.Matches.valid_picks?(socket.assigns.match, socket.assigns.current_player, Enum.map(picks, & &1.id)) do
      Game.update_team!(team, %{used_count: team.used_count + 1})
      {:noreply, assign(socket, picked_heroes: picks)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move-up", %{"id" => id}, socket) do
    {:noreply, move(String.to_integer(id), -1, socket)}
  end

  def handle_event("move-down", %{"id" => id}, socket) do
    {:noreply, move(String.to_integer(id), 1, socket)}
  end

  def handle_event("start", _, %{assigns: %{starting: true}} = socket), do: {:noreply, socket}

  def handle_event("start", _, %{assigns: %{match: match, picked_heroes: picked_heroes}} = socket) do
    ids = picked_heroes |> Enum.take(5) |> Enum.map(& &1.id)
    player = socket.assigns.current_player
    task = Task.Supervisor.async_nolink(Moba.TaskSupervisor, fn -> Game.start_match(match, player, ids) end)
    schedule_tick()
    {:noreply, assign(socket, tick: 0, starting: true, match_task_ref: task.ref)}
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

  def handle_info({:DOWN, ref, :process, _, _reason}, %{assigns: %{match_task_ref: ref}} = socket) do
    socket = socket_init(socket.assigns.match.id, @max_tick, assign(socket, starting: false, match_task_ref: nil))

    socket =
      if socket.assigns.match.phase == "scored" do
        socket
      else
        put_flash(socket, :error, "The match could not start. Please try again.")
      end

    {:noreply, socket}
  end

  def handle_info({:DOWN, _, _, _, _}, socket), do: {:noreply, socket}

  def handle_info({ref, {:error, _}}, %{assigns: %{match_task_ref: ref}} = socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    socket = assign(socket, starting: false, match_task_ref: nil)
    {:noreply, socket_init(socket.assigns.match.id, @max_tick, socket)}
  end

  def handle_info({ref, {:ok, match}}, %{assigns: %{match_task_ref: ref}} = socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    socket = assign(socket, starting: false, match_task_ref: nil)
    {:noreply, socket_init(match.id, socket.assigns.tick, socket)}
  end

  def handle_info({ref, _result}, socket) when is_reference(ref), do: {:noreply, socket}

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
      match_task_ref: Map.get(socket.assigns, :match_task_ref),
      battles: battles,
      tick: tick,
      trained_heroes: trained_heroes,
      picked_heroes: Enum.filter(match.player_picks, & &1),
      generated_heroes: available_heroes(match, player, trained_heroes),
      tutorial_step: player.tutorial_step,
      hero_tab: hero_tab,
      latest_match: latest_match,
      teams: teams,
      starting: Map.get(socket.assigns, :starting, false) && is_nil(match.phase),
      show_battle_details: Map.get(socket.assigns, :show_battle_details, false),
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

  defp eliminated?(hero, player, battles) do
    Enum.any?(battles, fn battle ->
      battler = turn_hero_for(battle, player)
      battler.hero_id == hero.id && battler.current_hp <= 0
    end)
  end

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
