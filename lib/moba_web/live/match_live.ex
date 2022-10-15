defmodule MobaWeb.MatchLive do
  use MobaWeb, :live_view
  # remove
  import Ecto.Query

  alias MobaWeb.MatchView

  @tick_timeout 500

  def mount(%{"id" => match_id}, _, socket) do
    with %{assigns: %{channel: channel}} = socket = socket_init(match_id, 100, socket) do
      if connected?(socket), do: MobaWeb.subscribe(channel)

      {:ok, socket}
    end
  end

  def handle_event("start", _, %{assigns: %{match: match}} = socket) do
    Task.Supervisor.async_nolink(Moba.TaskSupervisor, fn -> Game.continue_match!(match) end)
    schedule_tick()
    
    {:noreply, assign(socket, tick: 0)}
  end

  def handle_event("reset", _, %{assigns: %{match: match}} = socket) do
    Moba.Game.Matches.update!(match, %{winner_id: nil})
    query = from(b in Moba.Engine.Schema.Battle, where: b.match_id == ^match.id)
    Moba.Repo.delete_all(query)
    {:noreply, socket_init(match.id, 0, socket)}
  end

  def handle_info(:tick, %{assigns: %{tick: tick, match: %{id: match_id, winner_id: winner_id}}} = socket) when is_nil(winner_id) do
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
         match = Game.get_match!(match_id),
         battles = Engine.list_match_battles(match_id) do
      assign(socket,
        channel: channel,
        match: match,
        battles: battles,
        tick: tick
      )
    end
  end
end
