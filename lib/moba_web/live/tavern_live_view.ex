defmodule MobaWeb.TavernLiveView do
  use Phoenix.LiveView

  alias MobaWeb.TavernView
  alias Moba.{Game, Accounts}

  def mount(_, session, socket) do
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    user = Accounts.get_user_with_unlocks!(session["user_id"])

    skills = Game.list_unlockable_skills()
    avatars = Game.list_unlockable_avatars()
    all_avatars = Game.list_avatars()

    {:ok,
     assign(socket, current_user: user, current_hero: hero, skills: skills, avatars: avatars, all_avatars: all_avatars)}
  end

  def handle_event("unlock-avatar", %{"code" => code}, socket) do
    resource = Game.get_avatar_by_code!(code)
    user = Accounts.create_unlock!(socket.assigns.current_user, resource)
    {:noreply, assign(socket, current_user: user)}
  end

  def handle_event("unlock-skill", %{"code" => code}, socket) do
    resource = Game.get_current_skill!(code, 1)
    user = Accounts.create_unlock!(socket.assigns.current_user, resource)
    {:noreply, assign(socket, current_user: user)}
  end

  def render(assigns) do
    TavernView.render("index.html", assigns)
  end
end
