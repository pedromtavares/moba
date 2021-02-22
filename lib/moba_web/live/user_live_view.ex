defmodule MobaWeb.UserLiveView do
  use MobaWeb, :live_view

  def mount(_, session, socket) do
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)

    {:ok, assign(socket, current_hero: hero)}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    user = Accounts.get_user!(id)
    heroes = Game.latest_heroes(user.id)
    featured = Enum.sort_by(heroes, &(&1.total_farm), :desc) |> List.first()
    ranking = Accounts.user_search(user)

    {:noreply, assign(socket, user: user, featured: Game.get_hero!(featured.id), ranking: ranking, heroes: heroes)}
  end

  def handle_event("set-featured", %{"id" => id}, socket) do
    featured = Game.get_hero!(id)
    {:noreply, assign(socket, featured: featured)}
  end

  def render(assigns) do
    MobaWeb.UserView.render("show.html", assigns)
  end
end
