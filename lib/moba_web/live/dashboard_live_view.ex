defmodule MobaWeb.DashboardLiveView do
  use MobaWeb, :live_view

  def mount(_, session, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)

    {:ok, socket |> pve_assigns() |> quest_assigns()}
  end

  def handle_event("pve-show-finished", _, socket) do
    {:noreply, assign(socket, visible_heroes: finished_heroes(socket.assigns.all_heroes), pve_display: "finished")}
  end

  def handle_event("pve-show-unfinished", _, socket) do
    {:noreply, assign(socket, visible_heroes: unfinished_heroes(socket.assigns.all_heroes), pve_display: "unfinished")}
  end

  def handle_event("archive", %{"id" => id}, socket) do
    hero = Game.get_hero!(id)
    Game.archive_hero!(hero)
    if hero.finished_at, do: Game.update_hero_collection!(hero)

    {:noreply, assign(socket, visible_heroes: Enum.reject(socket.assigns.visible_heroes, &(&1.id == hero.id)))}
  end

  def render(assigns) do
    MobaWeb.DashboardView.render("index.html", assigns)
  end

  defp pve_assigns(%{assigns: %{current_user: user}} = socket) do
    all_heroes = Game.latest_heroes(user.id)
    unfinished_heroes = unfinished_heroes(all_heroes)
    pve_display = if Enum.any?(unfinished_heroes), do: "unfinished", else: "finished"
    visible_heroes = if pve_display == "unfinished", do: unfinished_heroes, else: finished_heroes(all_heroes)
    collection_codes = Enum.map(user.hero_collection, & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))

    assign(socket,
      all_heroes: all_heroes,
      unfinished_heroes: unfinished_heroes,
      pve_display: pve_display,
      visible_heroes: visible_heroes,
      collection_codes: collection_codes,
      blank_collection: blank_collection
    )
  end

  defp unfinished_heroes(all_heroes), do: Enum.filter(all_heroes, &is_nil(&1.finished_at))

  defp finished_heroes(all_heroes), do: Enum.filter(all_heroes, & &1.finished_at)

  defp quest_assigns(%{assigns: %{current_user: user}} = socket) do
    season_progressions = Game.list_season_quest_progressions(user.id)
    current_season_progression = Game.active_quest_progression?(season_progressions)
    daily_progressions = Game.list_daily_quest_progressions(user.id)

    assign(socket,
      season_progressions: season_progressions,
      current_season_progression: current_season_progression,
      daily_progressions: daily_progressions
    )
  end
end
