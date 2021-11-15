defmodule MobaWeb.DashboardLiveView do
  use MobaWeb, :live_view

  alias Moba.{Accounts, Game}

  def mount(_, session, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)

    {:ok, socket |> pve_assigns() |> pvp_assigns() |> quest_assigns()}
  end

  def handle_event("achievements-display", %{"display" => display}, socket) do
    {:noreply, assign(socket, achievements_display: display)}
  end

  def handle_event("daily-display", %{"display" => display}, socket) do
    {:noreply, assign(socket, daily_display: display)}
  end

  def handle_event("pve-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, current_pve_tab: tab)}
  end

  def handle_event("pve-season-progression", %{"level" => level}, socket) do
    progression = Enum.find(socket.assigns.season_progressions, &(&1.quest.level == String.to_integer(level)))
    {:noreply, assign(socket, current_season_progression: progression)}
  end

  def handle_event("pve-show-finished", _, socket) do
    {:noreply, assign(socket, visible_heroes: finished_heroes(socket.assigns.all_heroes), pve_display: "finished")}
  end

  def handle_event("pve-show-unfinished", _, socket) do
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

  defp pve_assigns(%{assigns: %{current_user: user}} = socket) do
    all_heroes = Game.latest_heroes(user.id)
    unfinished_heroes = unfinished_heroes(all_heroes)
    pve_display = if Enum.any?(unfinished_heroes), do: "unfinished", else: "finished"
    visible_heroes = if pve_display == "unfinished", do: unfinished_heroes, else: finished_heroes(all_heroes)

    assign(socket,
      all_heroes: all_heroes,
      unfinished_heroes: unfinished_heroes,
      pve_display: pve_display,
      visible_heroes: visible_heroes
    )
  end

  defp unfinished_heroes(all_heroes), do: Enum.filter(all_heroes, &(not &1.finished_pve))
  defp finished_heroes(all_heroes), do: Enum.filter(all_heroes, & &1.finished_pve)

  defp pvp_assigns(%{assigns: %{current_user: user}} = socket) do
    current_pvp_hero = Game.current_pvp_hero(user)
    last_match = Game.last_match()
    last_pvp_hero = Game.last_picked_pvp_hero(user.id)
    winners = Game.podium_for(last_match)

    tier_winners =
      if last_pvp_hero && last_pvp_hero.league_tier == Moba.master_league_tier(),
        do: winners["master"],
        else: winners["grandmaster"]

    winner_index = tier_winners && Enum.find_index(tier_winners, fn winner -> winner.user_id == user.id end)

    pvp_display = if current_pvp_hero, do: "current", else: "previous"
    pvp_hero = if current_pvp_hero, do: current_pvp_hero, else: last_pvp_hero

    duel_users = if user.status == "available", do: Accounts.list_duel_users(user), else: []

    assign(socket,
      current_pvp_hero: current_pvp_hero,
      duel_users: duel_users,
      last_pvp_hero: last_pvp_hero,
      pvp_hero: pvp_hero,
      pvp_display: pvp_display,
      winners: tier_winners,
      winner_index: winner_index
    )
  end

  defp quest_assigns(%{assigns: %{current_user: user}} = socket) do
    current_master_collection = Enum.filter(user.hero_collection, fn hero -> hero["tier"] >= 5 end)
    season_progressions = Game.list_quest_progressions(user.id, "season")
    current_season_progression = Game.active_quest_progression?(season_progressions)
    daily_progressions = Game.list_daily_quest_progressions(user.id)
    achievement_progressions = Game.list_achievement_progressions(user.id)
    current_pve_tab = if current_season_progression, do: "season", else: "daily"

    assign(socket,
      current_master_collection: current_master_collection,
      season_progressions: season_progressions,
      current_season_progression: current_season_progression,
      daily_display: "pve",
      daily_progressions: daily_progressions,
      achievements_display: "in_progress",
      achievement_progressions: achievement_progressions,
      current_pve_tab: current_pve_tab
    )
  end
end
