defmodule MobaWeb.HallLiveView do
  use MobaWeb, :live_view

  def mount(_, session, socket) do
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)

    pve = Game.pve_ranking(20)

    tabs = ["pve", "pvp", "users"]

    {:ok, assign(socket, current_hero: hero, pve: pve, pvp: nil, users: nil, active_tab: "pve")}
  end

  def handle_event("show-users", _, socket) do
    users = if socket.assigns.users, do: socket.assigns.users, else: Accounts.ranking(20)
    {:noreply, assign(socket, active_tab: "users", users: users)}
  end

  def handle_event("show-pvp", _, socket) do
    pvp = if socket.assigns.pvp, do: socket.assigns.pvp, else: Game.pvp_ranking(20)
    {:noreply, assign(socket, active_tab: "pvp", pvp: pvp)}
  end

  def handle_event("show-pve", _, socket) do
    {:noreply, assign(socket, active_tab: "pve")}
  end

  def render(assigns) do
    MobaWeb.HallView.render("index.html", assigns)
  end
end
