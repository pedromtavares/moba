defmodule MobaWeb.Admin.MatchLiveView do
  use MobaWeb, :live_view

  alias Moba.{Game, Admin}

  def mount(_, _, socket) do
    if connected?(socket), do: MobaWeb.subscribe("admin")

    duels = Admin.list_recent_duels()

    {:ok, assign(socket, match: Game.current_match(), duels: duels) |> set_vars()}
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
    sorted_guests = Enum.sort_by(data.guests, &(&1.current_pve_hero.league_tier), :desc)

    assign(socket,
      players: data.players,
      guests: sorted_guests,
      user_stats: user_stats,
      last_updated: Timex.now()
    )
  end
end
