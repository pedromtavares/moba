defmodule MobaWeb.DashboardLiveView do
  use MobaWeb, :live_view

  alias Moba.{Accounts, Game}

  def mount(_, session, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)
    user = socket.assigns.current_user

    all_heroes = Game.latest_heroes(user.id)
    unfinished_heroes = unfinished_heroes(all_heroes)
    pve_display = if Enum.any?(unfinished_heroes), do: "unfinished", else: "finished"
    visible_heroes = if pve_display == "unfinished", do: unfinished_heroes, else: finished_heroes(all_heroes)

    current_pvp_hero = Game.current_pvp_hero(user)

    last_match = Game.last_match()
    last_pvp_hero = Game.last_pvp_hero(user.id)
    winners = Game.podium_for(last_match)

    tier_winners =
      if last_pvp_hero && last_pvp_hero.league_tier == Moba.master_league_tier(),
        do: winners["master"],
        else: winners["grandmaster"]

    winner_index = tier_winners && Enum.find_index(tier_winners, fn winner -> winner.user_id == user.id end)

    pvp_display = if current_pvp_hero, do: "current", else: "previous"
    pvp_hero = if current_pvp_hero, do: current_pvp_hero, else: last_pvp_hero

    duel_users = if user.status == "available", do: Accounts.list_duel_users(user), else: []

    {:ok,
     assign(socket,
       current_pvp_hero: current_pvp_hero,
       last_pvp_hero: last_pvp_hero,
       pvp_hero: pvp_hero,
       all_heroes: all_heroes,
       visible_heroes: visible_heroes,
       pve_display: pve_display,
       pvp_display: pvp_display,
       winners: tier_winners,
       winner_index: winner_index,
       duel_users: duel_users
     )}
  end

  def handle_event("show-finished", _, socket) do
    {:noreply, assign(socket, visible_heroes: finished_heroes(socket.assigns.all_heroes), pve_display: "finished")}
  end

  def handle_event("show-unfinished", _, socket) do
    {:noreply, assign(socket, visible_heroes: unfinished_heroes(socket.assigns.all_heroes), pve_display: "unfinished")}
  end

  def handle_event("show-current", _, socket) do
    {:noreply, assign(socket, pvp_hero: socket.assigns.current_pvp_hero, pvp_display: "current")}
  end

  def handle_event("show-previous", _, socket) do
    {:noreply, assign(socket, pvp_hero: socket.assigns.last_pvp_hero, pvp_display: "previous")}
  end

  def handle_event("archive", %{"id" => id}, socket) do
    hero = Game.get_hero!(id)
    Game.archive_hero!(hero)
    {:noreply, assign(socket, visible_heroes: Enum.reject(socket.assigns.visible_heroes, &(&1.id == hero.id)))}
  end

  def handle_event("challenge", %{"id" => opponent_id}, socket) do
    opponent = Accounts.get_user!(opponent_id)
    Game.duel_challenge(socket.assigns.current_user, opponent)

    {:noreply, socket}
  end

  def render(assigns) do
    MobaWeb.DashboardView.render("index.html", assigns)
  end

  defp unfinished_heroes(all_heroes), do: Enum.filter(all_heroes, &(not &1.finished_pve))
  defp finished_heroes(all_heroes), do: Enum.filter(all_heroes, & &1.finished_pve)
end
