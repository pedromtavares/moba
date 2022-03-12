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

    completed_season_progression =
      completed_progressions &&
        Enum.find(completed_progressions, &Enum.member?(Moba.season_quest_codes(), &1.quest.code))

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

  def handle_event(
        "set-skin",
        %{"skin-code" => skin_code},
        %{assigns: %{skin_selection: selection, hero: hero}} = socket
      ) do
    skin = Enum.find(selection.skins, &(&1.code == skin_code))

    updated_hero = Game.set_hero_skin!(hero, skin)

    skin_index = Enum.find_index(selection.skins, fn selection_skin -> selection_skin.code == skin_code end)
    updated_selection = %{selection | index: skin_index}

    {:noreply, assign(socket, hero: updated_hero, skin_selection: updated_selection)}
  end

  def handle_info({"hero", %{id: id}}, socket) do
    {:noreply, assign(socket, hero: Game.get_hero!(id))}
  end

  def handle_info({"ranking", _}, %{assigns: %{hero: %{id: id}}} = socket) do
    hero = Game.get_hero!(id)
    {:noreply, assign(socket, ranking: Game.pve_search(hero), hero: hero)}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    hero = Game.get_hero!(id)
    ranking = Game.pve_search(hero)
    user = socket.assigns.current_user

    if connected?(socket) do
      Game.subscribe_to_hero(id)
      MobaWeb.subscribe("hero-ranking")
    end

    skin_selection =
      if hero.user_id == user.id do
        skins = Accounts.unlocked_codes_for(user) |> Game.list_skins_with_codes()
        avatar_code = hero.avatar.code
        avatar_skins = [Game.default_skin(avatar_code)] ++ Enum.filter(skins, &(&1.avatar_code == avatar_code))
        index = Enum.find_index(avatar_skins, fn skin -> skin.id == hero.skin_id end)

        %{
          index: index,
          skins: avatar_skins
        }
      end

    {:noreply, assign(socket, hero: hero, ranking: ranking, skin_selection: skin_selection)}
  end

  def render(assigns) do
    MobaWeb.HeroView.render("show.html", assigns)
  end

  defp tab_display_priority(season) when not is_nil(season), do: "season"
  defp tab_display_priority(_), do: "daily"
end
