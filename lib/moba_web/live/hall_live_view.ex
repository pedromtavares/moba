defmodule MobaWeb.HallLiveView do
  use Phoenix.LiveView

  alias MobaWeb.HallView
  alias Moba.{Game, Accounts}

  def mount(_, session, socket) do
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)

    heroes = Game.ranking(20)

    {:ok, assign(socket, current_hero: hero, heroes: heroes, users: nil, show_users: false)}
  end

  def handle_event("show-users", _, socket) do
    users = Accounts.ranking(20)
    {:noreply, assign(socket, show_users: true, users: users)}
  end

  def handle_event("show-heroes", _, socket) do
    {:noreply, assign(socket, show_users: false)}
  end

  def render(assigns) do
    HallView.render("index.html", assigns)
  end
end
