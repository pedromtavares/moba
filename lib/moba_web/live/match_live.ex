defmodule MobaWeb.MatchLive do
  use MobaWeb, :live_view
  # remove
  import Ecto.Query

  alias MobaWeb.{MatchView, TutorialComponent}

  @tick_timeout 500

  def mount(%{"id" => match_id}, _, socket) do
    with %{assigns: %{channel: channel}} = socket = socket_init(match_id, 100, socket) do
      if connected?(socket), do: MobaWeb.subscribe(channel)

      {:ok, socket}
    end
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

  def handle_event("start", _, %{assigns: %{match: match, picked_heroes: picked_heroes}} = socket) do
    ids = Enum.map(picked_heroes, & &1.id)
    Task.Supervisor.async_nolink(Moba.TaskSupervisor, fn -> Game.continue_match!(match, ids) end)
    schedule_tick()

    {:noreply, assign(socket, tick: 0)}
  end

  def handle_event("reset", _, %{assigns: %{match: match}} = socket) do
    Moba.Game.Matches.update!(match, %{winner_id: nil, phase: nil})
    query = from(b in Moba.Engine.Schema.Battle, where: b.match_id == ^match.id)
    Moba.Repo.delete_all(query)
    {:noreply, socket_init(match.id, 0, socket)}
  end

  def handle_event("finish-tutorial", _, socket) do
    {:noreply, TutorialComponent.finish_arena(socket)}
  end

  def handle_info({:tutorial, %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def handle_info(:tick, %{assigns: %{tick: tick, match: %{id: match_id, winner_id: winner_id}}} = socket)
      when is_nil(winner_id) do
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

  def handle_info({ref, match}, socket) do
    Process.demonitor(ref, [:flush])

    {:noreply, socket_init(match.id, socket.assigns.tick, socket)}
  end

  def render(assigns) do
    MatchView.render("show.html", assigns)
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_timeout)

  defp socket_init(match_id, tick, socket) do
    with channel = "match-#{match_id}",
         player = socket.assigns.current_player,
         match = Game.get_match!(match_id),
         latest_match = Game.latest_manual_match(player),
         battles = Engine.list_match_battles(match_id),
         trained_heroes = Game.trained_pvp_heroes(player.id, [], 20) do
      assign(socket,
        channel: channel,
        match: match,
        battles: battles,
        tick: tick,
        trained_heroes: trained_heroes,
        picked_heroes: match.player_picks,
        generated_heroes: match.generated_picks,
        tutorial_step: player.tutorial_step,
        hero_tab: "trained",
        latest_match: latest_match
      )
    end
  end
end
