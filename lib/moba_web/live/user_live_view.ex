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

    {:noreply,
     assign(socket,
       user: user,
       featured: featured,
       ranking: ranking,
       blank_collection: blank_collection,
       arena_picks: arena_picks
     )}
  end

  def handle_event("set-featured", %{"id" => id}, socket) do
    featured = Game.get_hero!(id)
    {:noreply, assign(socket, featured: featured)}
  end

  def render(assigns) do
    MobaWeb.UserView.render("show.html", assigns)
  end
end
