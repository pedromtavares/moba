defmodule MobaWeb.DashboardLiveView do
  use MobaWeb, :live_view

  alias MobaWeb.Tutorial

  @base_hero_count Moba.base_hero_count()

  def mount(_, _session, %{assigns: %{current_user: user}} = socket) do
    if connected?(socket), do: Tutorial.subscribe(user.id)

    {:ok,
     socket
     |> assign(sidebar_code: "base", tutorial_step: user.tutorial_step)
     |> pve_assigns()
     |> quest_assigns()
     |> check_tutorial()}
  end

  def handle_event("pve-show-finished", _, %{assigns: %{all_heroes: all_heroes, loaded: loaded}} = socket) do
    visible = finished_heroes(all_heroes)
    loaded = if length(visible) < @base_hero_count, do: loaded ++ ["finished"], else: loaded
    {:noreply, assign(socket, loaded: loaded, visible_heroes: visible, pve_display: "finished")}
  end

  def handle_event("pve-show-unfinished", _, %{assigns: %{all_heroes: all_heroes, loaded: loaded}} = socket) do
    visible = unfinished_heroes(all_heroes)
    loaded = if length(visible) < @base_hero_count, do: loaded ++ ["unfinished"], else: loaded
    {:noreply, assign(socket, loaded: loaded, visible_heroes: visible, pve_display: "unfinished")}
  end

  def handle_event(
        "load-all",
        _,
        %{assigns: %{pve_display: display, current_user: user, all_heroes: all_heroes, loaded: loaded}} = socket
      ) do
    visible =
      if display == "finished" do
        Game.list_all_finished_heroes(user.id)
      else
        Game.list_all_unfinished_heroes(user.id)
      end

    all_heroes = Enum.uniq(all_heroes ++ visible)

    {:noreply, assign(socket, visible_heroes: visible, all_heroes: all_heroes, loaded: loaded ++ [display])}
  end

  def handle_event("archive", %{"id" => id}, %{assigns: %{current_user: user, current_hero: current_hero}} = socket) do
    hero = Game.get_hero!(id)

    if hero.user_id == user.id do
      Game.archive_hero!(hero)
      if hero.finished_at, do: Game.update_hero_collection!(hero)

      current_hero = if current_hero && hero.id == current_hero.id, do: nil, else: current_hero

      {:noreply,
       assign(socket,
         current_hero: current_hero,
         visible_heroes: Enum.reject(socket.assigns.visible_heroes, &(&1.id == hero.id))
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("continue", %{"id" => id}, %{assigns: %{current_user: user}} = socket) do
    hero = Game.get_hero!(id)

    if hero.user_id == user.id do
      user = Accounts.set_current_pve_hero!(user, id)

      {:noreply,
       assign(socket, current_hero: hero, current_user: user)
       |> push_redirect(to: Routes.live_path(socket, MobaWeb.TrainingLiveView))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("tutorial1", _, socket) do
    {:noreply, socket |> Tutorial.next_step(21)}
  end

  def handle_event("finish-tutorial", _, socket) do
    {:noreply, Tutorial.finish_base(socket)}
  end

  def handle_info({"tutorial-step", %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def render(assigns) do
    MobaWeb.DashboardView.render("index.html", assigns)
  end

  defp check_tutorial(%{assigns: %{current_user: user}} = socket) do
    %{assigns: %{tutorial_step: step}} = socket = Tutorial.next_step(socket, 20)

    if step == 29 && user.pve_tier > 0 do
      socket
      |> Tutorial.next_step(30)
      |> push_redirect(to: Routes.live_path(socket, MobaWeb.ArenaLiveView))
    else
      socket
    end
  end

  defp pve_assigns(%{assigns: %{current_user: user}} = socket) do
    unfinished_heroes = Game.latest_unfinished_heroes(user.id)
    finished_heroes = Game.latest_finished_heroes(user.id)
    all_heroes = unfinished_heroes ++ finished_heroes
    pve_display = if Enum.any?(unfinished_heroes), do: "unfinished", else: "finished"
    visible_heroes = if pve_display == "unfinished", do: unfinished_heroes, else: finished_heroes
    collection_codes = Enum.map(user.hero_collection, & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))
    loaded = if length(visible_heroes) < @base_hero_count, do: [pve_display], else: []

    assign(socket,
      all_heroes: all_heroes,
      unfinished_heroes: unfinished_heroes,
      pve_display: pve_display,
      visible_heroes: visible_heroes,
      collection_codes: collection_codes,
      blank_collection: blank_collection,
      loaded: loaded
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
