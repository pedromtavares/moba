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

  def handle_event("stats-filter", params, socket) do
    with filter = Map.get(params, "type") do
      {:noreply, assign(socket, stats_filter: filter) |> base_assigns()}
    end
  end

  def render(assigns) do
    MobaWeb.Admin.SeasonView.render("show.html", assigns)
  end

  defp base_assigns(socket) do
    data = Admin.get_server_data()

    filter = socket.assigns[:filter] || :weekly
    stats_filter = socket.assigns[:stats_filter] || "pvp"

    assign(socket,
      players: data.players,
      guests: data.guests,
      filter: filter,
      user_stats: data.user_stats[filter],
      stats_filter: stats_filter,
      match_stats: data.match_stats[stats_filter],
      duels: data.duels,
      last_updated: Timex.now()
    )
  end
end
