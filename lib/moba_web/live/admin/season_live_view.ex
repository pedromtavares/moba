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

  def handle_event("filter", _, %{assigns: %{filter: filter}} = socket) do
    new_filter = if filter == :weekly, do: :daily, else: :weekly
    {:noreply, assign(socket, filter: new_filter) |> base_assigns()}
  end

  def render(assigns) do
    MobaWeb.Admin.SeasonView.render("show.html", assigns)
  end

  defp base_assigns(socket) do
    data = Admin.get_server_data()

    filter = socket.assigns[:filter] || :weekly

    assign(socket,
      players: data.players,
      guests: data.guests,
      filter: filter,
      user_stats: data.user_stats[filter],
      duels: data.duels,
      last_updated: Timex.now()
    )
  end
end
