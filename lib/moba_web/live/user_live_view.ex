defmodule MobaWeb.UserLiveView do
  use MobaWeb, :live_view

  def mount(_, session, socket) do
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)

    {:ok, assign(socket, current_hero: hero)}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    user = Accounts.get_user_with_current_heroes!(id)

    featured =
      if length(user.hero_collection) > 0 do
        hero = List.first(user.hero_collection)
        Game.get_hero!(hero["hero_id"])
      else
        Game.current_hero(user)
      end

    collection_codes = Enum.map(user.hero_collection, & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))
    ranking = Accounts.user_search(user)
    arena_picks = Game.list_recent_arena_picks(user)
    available_title_quests = Game.list_title_quests(user.id)

    {:noreply,
     assign(socket,
       user: user,
       featured: featured,
       ranking: ranking,
       blank_collection: blank_collection,
       arena_picks: arena_picks,
       available_title_quests: available_title_quests,
       editing: false
     )}
  end

  def handle_event("set-featured", %{"id" => id}, socket) do
    featured = Game.get_hero!(id)
    {:noreply, assign(socket, featured: featured)}
  end

  def handle_event("start-editing", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("update", %{"quest_id" => quest_id}, socket) do
    updated = Accounts.update_user!(socket.assigns.user, %{title_quest_id: quest_id})
    {:noreply, assign(socket, editing: false, user: Accounts.get_user_with_current_heroes!(updated.id))}
  end

  def render(assigns) do
    MobaWeb.UserView.render("show.html", assigns)
  end
end
