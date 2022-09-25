defmodule MobaWeb.MatchLive do
  use MobaWeb, :live_view

  alias MobaWeb.MatchView

  def mount(%{"id" => match_id}, _, socket) do
    with %{assigns: %{channel: channel}} = socket = socket_init(match_id, socket) do
      if connected?(socket), do: MobaWeb.subscribe(channel)

      {:ok, socket}
    end
  end

  def handle_event("start", _, %{assigns: %{match: match}} = socket) do
    with _match = Game.start_match!(match) do
      {:noreply, socket}
    end
  end

  def handle_info({"latest", _}, %{assigns: %{match: match}} = socket) do
    with battles = Engine.list_match_battles(match.id) do
      {:noreply, assign(socket, battles: battles)}
    end
  end

  def render(assigns) do
    MatchView.render("show.html", assigns)
  end

  defp socket_init(match_id, socket) do
    with channel = "match-#{match_id}",
         match = Game.get_match!(match_id),
         battles = Engine.list_match_battles(match_id) do
      assign(socket,
        channel: channel,
        match: match,
        battles: battles
      )
    end
  end
end
