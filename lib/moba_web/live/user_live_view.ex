defmodule MobaWeb.UserLiveView do
  use MobaWeb, :live_view

  def mount(_, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, %{assigns: %{current_user: current_user}} = socket) do
    if connected?(socket) do
      MobaWeb.subscribe("user-ranking")
    end

    user = Accounts.get_user_with_current_heroes!(id)
    code = if user.id == current_user.id, do: "user", else: nil

    featured =
      if length(user.hero_collection) > 0 do
        hero = List.first(user.hero_collection)
        Game.get_hero!(hero["hero_id"])
      else
        Game.current_pve_hero(user)
      end

    collection_codes = Enum.map(user.hero_collection, & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))
    ranking = Accounts.search(user)
    duels = Game.list_finished_duels(user)

    {:noreply,
     assign(socket,
       user: user,
       featured: featured,
       ranking: ranking,
       blank_collection: blank_collection,
       duels: duels,
       sidebar_code: code
     )}
  end

  def handle_event("set-featured", %{"id" => id}, socket) do
    featured = Game.get_hero!(id)
    {:noreply, assign(socket, featured: featured)}
  end

  def handle_info({"ranking", _}, %{assigns: %{user: %{id: id}}} = socket) do
    user = Accounts.get_user!(id)
    {:noreply, assign(socket, ranking: Accounts.search(user), user: user)}
  end

  def render(assigns) do
    MobaWeb.UserView.render("show.html", assigns)
  end
end
