defmodule MobaWeb.TavernLiveView do
  use MobaWeb, :live_view

  def mount(_, session, socket) do
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    user = Accounts.get_user_with_unlocks!(session["user_id"])

    skills = Game.list_unlockable_skills()
    avatars = Game.list_unlockable_avatars()
    all_avatars = Game.list_avatars() |> Enum.sort_by(& &1.level_requirement, :desc)

    {:ok,
     assign(socket,
       current_user: user,
       current_hero: hero,
       skills: skills,
       avatars: avatars,
       all_avatars: all_avatars,
       current_index: 0
     )}
  end

  def handle_params(params, _uri, %{assigns: %{all_avatars: all_avatars}} = socket) do
    avatar_code = Map.get(params, "avatar")
    current_avatar = Enum.find(all_avatars, &(&1.code == avatar_code)) || List.first(all_avatars)
    current_skins = Game.list_skins_for(current_avatar.code)
    current_skin = List.first(current_skins)

    {:noreply,
     assign(socket,
       current_avatar: current_avatar,
       current_skins: current_skins,
       # current_skin
       current_skin: false
     )}
  end

  def handle_event("previous-skin", _, socket) do
    index = socket.assigns.current_index - 1
    skin = Enum.at(socket.assigns.current_skins, index)
    {:noreply, assign(socket, current_skin: skin, current_index: index)}
  end

  def handle_event("next-skin", _, socket) do
    index = socket.assigns.current_index + 1
    skin = Enum.at(socket.assigns.current_skins, index)
    {:noreply, assign(socket, current_skin: skin, current_index: index)}
  end

  def handle_event("set-avatar", %{"code" => code}, %{assigns: %{all_avatars: all_avatars}} = socket) do
    avatar = Enum.find(all_avatars, &(&1.code == code))
    skins = Game.list_skins_for(code)
    skin = List.first(skins)
    {:noreply, assign(socket, current_avatar: avatar, current_skins: skins, current_skin: skin, current_index: 0)}
  end

  def handle_event("set-skin", %{"code" => code}, socket) do
    skin = Enum.find(socket.assigns.current_skins, &(&1.code == code))
    {:noreply, assign(socket, current_skin: skin)}
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

  def handle_event("unlock-skin", %{"code" => code}, socket) do
    resource = Game.get_skin_by_code!(code)
    user = Accounts.create_unlock!(socket.assigns.current_user, resource)
    {:noreply, assign(socket, current_user: user)}
  end

  def render(assigns) do
    MobaWeb.TavernView.render("index.html", assigns)
  end
end
