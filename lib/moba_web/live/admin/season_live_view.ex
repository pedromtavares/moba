defmodule MobaWeb.Admin.SeasonLiveView do
  use MobaWeb, :live_view

  alias Moba.Admin

  def mount(_, _, socket) do
    if connected?(socket), do: MobaWeb.subscribe("admin")

    {:ok, base_assigns(socket)}
  end

  def handle_info({"server", _}, socket) do
    {:noreply, base_assigns(socket)}
  end

  def render(assigns) do
    MobaWeb.Admin.SeasonView.render("show.html", assigns)
  end

  defp base_assigns(socket) do
    data = Admin.get_server_data()

    assign(socket,
      players: data.players,
      guests: data.guests,
      user_stats: data.user_stats,
      duels: data.duels,
      last_updated: Timex.now()
    )
  end
end
