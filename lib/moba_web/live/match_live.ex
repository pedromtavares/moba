defmodule MobaWeb.MatchLive do
  use MobaWeb, :live_view

  alias MobaWeb.{MatchView, TutorialComponent}

  @tick_timeout 500
  @max_tick 15

  def mount(%{"id" => match_id}, _, socket) do
    with %{assigns: %{channel: channel}} = socket = socket_init(match_id, @max_tick, socket) do
      if connected?(socket), do: MobaWeb.subscribe(channel)

      {:ok, socket}
    end
  end

  def handle_event("hero-tab", %{"type" => tab}, socket) do
    {:noreply, assign(socket, hero_tab: tab)}
  end

  def handle_event("repeat", _, %{assigns: %{latest_match: match, trained_heroes: trained}} = socket)
      when not is_nil(match) do
    trained_ids = Enum.map(trained, & &1.id)
    picked_heroes = Enum.filter(match.player_picks, &Enum.member?(trained_ids, &1.id))
    {:noreply, assign(socket, picked_heroes: picked_heroes)}
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

  def handle_info(:tick, socket) do
    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, _, _, _reason}, %{assigns: %{match: match}} = socket) do
    match = Game.reset_match!(match)
    {:noreply, socket_init(match.id, @max_tick, socket)}
  end

  def handle_info({ref, match}, socket) do
    Process.demonitor(ref, [:flush])

    {:noreply, socket_init(match.id, socket.assigns.tick, socket)}
  end

  def render(assigns) do
    MatchView.render("show.html", assigns)
  end

  defp available_heroes(match, %{pvp_tier: 0}, _) do
    match.generated_picks
  end

  defp available_heroes(_, _, trained_heroes) do
    Moba.pve_ranking_available() |> Enum.reject(&Enum.member?(trained_heroes, &1)) |> Enum.take(10)
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_timeout)

  defp socket_init(match_id, tick, socket) do
    with channel = "match-#{match_id}",
         player = socket.assigns.current_player,
         match = Game.get_match!(match_id),
         latest_match = Game.latest_manual_match(player),
         battles = Engine.list_match_battles(match_id),
         teams = Game.list_teams(player),
         hero_tab = if(length(teams) > 0, do: "teams", else: "trained"),
         trained_heroes = Game.trained_pvp_heroes(player.id, [], 20),
         generated_heroes = available_heroes(match, player, trained_heroes) do
      assign(socket,
        channel: channel,
        match: match,
        battles: battles,
        tick: tick,
        trained_heroes: trained_heroes,
        picked_heroes: match.player_picks,
        generated_heroes: generated_heroes,
        tutorial_step: player.tutorial_step,
        hero_tab: hero_tab,
        latest_match: latest_match,
        teams: teams
      )
    end
  end
end
