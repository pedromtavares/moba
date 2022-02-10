defmodule MobaWeb.Admin.MatchLiveView do
  use MobaWeb, :live_view

  alias Moba.{Game, Admin}

  def mount(_, session, socket) do
    if connected?(socket), do: MobaWeb.subscribe("admin")

    match_id = Map.get(session, "match_id")

    match =
      case match_id do
        nil -> Game.current_match()
        "current" -> Game.current_match()
        _ -> Admin.get_match!(match_id)
      end

    duels = Admin.list_recent_duels()

    {:ok, assign(socket, match: match, duels: duels) |> set_vars()}
  end

  def handle_info({"server", _}, socket) do
    {:noreply, set_vars(socket)}
  end

  def render(assigns) do
    MobaWeb.Admin.MatchView.render("show.html", assigns)
  end

  defp set_vars(socket) do
    data = Admin.get_server_data(socket.assigns.match)
    user_stats = Admin.get_user_stats()

    assign(socket,
      players: data.players,
      user_stats: user_stats,
      last_updated: Timex.now()
    )
  end
end
