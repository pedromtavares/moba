defmodule MobaWeb.HeroLiveView do
  use MobaWeb, :live_view

  def mount(_, %{"user_id" => user_id} = session, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)
    user = socket.assigns.current_user
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    avatars = Game.list_avatars()
    collection_codes = Enum.map(user.hero_collection, & &1["code"])
    blank_collection = Enum.filter(avatars, &(&1.code not in collection_codes))
    
    completed_progressions = hero && Game.last_completed_quest_progressions(hero)
    completed_season_progression = completed_progressions && Enum.find(completed_progressions, &(&1.quest.code == "season"))
    completed_daily_progressions = completed_progressions && Enum.filter(completed_progressions, & &1.quest.daily)

    completed_season_progression =
      completed_progressions && Enum.find(completed_progressions, &String.contains?(&1.quest.code, "season"))

    completed_daily_progressions = completed_progressions && Enum.filter(completed_progressions, & &1.quest.daily)

    tab_display = tab_display_priority(completed_season_progression)

    {:ok,
     assign(socket,
       avatars: avatars,
       current_hero: hero,
       blank_collection: blank_collection,
       completed_progressions: completed_progressions,
       completed_season_progression: completed_season_progression,
       completed_daily_progressions: completed_daily_progressions,
       tab_display: tab_display
     )}
  end

  def handle_event("tab-display", %{"display" => display}, socket) do
    {:noreply, assign(socket, tab_display: display)}
  end

  def handle_info({"hero", %{id: id}}, socket) do
    {:noreply, assign(socket, hero: Game.get_hero!(id))}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    hero = Game.get_hero!(id)
    ranking = Game.pve_search(hero)

    if connected?(socket) do
      Game.subscribe_to_hero(id)
    end

    {:noreply, assign(socket, hero: hero, ranking: ranking)}
  end

  def render(assigns) do
    MobaWeb.HeroView.render("show.html", assigns)
  end

  defp tab_display_priority(season) when not is_nil(season), do: "season"
  defp tab_display_priority(_), do: "daily"
end
