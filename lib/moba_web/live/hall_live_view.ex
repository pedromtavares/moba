defmodule MobaWeb.HallLiveView do
  use MobaWeb, :live_view

  def mount(_, session, socket) do
    pve = Game.pve_ranking(20)

    {:ok, assign(socket, pve: pve, users: nil, active_tab: "pve", sidebar_code: "hall")}
  end

  def handle_event("show-users", _, socket) do
    users = if socket.assigns.users, do: socket.assigns.users, else: Accounts.ranking(20)
    {:noreply, assign(socket, active_tab: "users", users: users)}
  end

  def handle_event("show-pve", _, socket) do
    {:noreply, assign(socket, active_tab: "pve")}
  end

  def render(assigns) do
    MobaWeb.HallView.render("index.html", assigns)
  end
end
