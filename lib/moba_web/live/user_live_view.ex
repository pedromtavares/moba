defmodule MobaWeb.UserLiveView do
  use Phoenix.LiveView

  alias MobaWeb.UserView
  alias Moba.{Game, Accounts}

  def mount(_, session, socket) do
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)

    {:ok, assign(socket, current_hero: hero)}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    user = Accounts.get_user!(id)
    hero = Game.current_hero(user)
    heroes = Game.latest_heroes(user.id)

    {:noreply, assign(socket, user: user, hero: hero, show_heroes: true, heroes: heroes)}
  end

  def handle_event("show-heroes", _, socket) do
    {:noreply, assign(socket, show_heroes: true)}
  end

  def render(assigns) do
    UserView.render("show.html", assigns)
  end
end
