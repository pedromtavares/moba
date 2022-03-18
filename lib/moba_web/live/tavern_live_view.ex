defmodule MobaWeb.TavernLiveView do
  use MobaWeb, :live_view

  def mount(_, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, %{assigns: %{current_user: user}} = socket) do
    user = Accounts.get_user_with_unlocks!(user.id)
    skills = Game.list_unlockable_skills()
    avatars = Game.list_unlockable_avatars()
    all_avatars = Game.list_avatars() |> Enum.sort_by(& &1.level_requirement, :desc)
    avatar_code = Map.get(params, "avatar")
    current_avatar = Enum.find(all_avatars, &(&1.code == avatar_code)) || List.first(all_avatars)
    current_skins = Game.list_skins_for(current_avatar.code)
    current_skin = List.first(current_skins)

    {:noreply,
     assign(socket,
       all_avatars: all_avatars,
       avatars: avatars,
       avatar_code: avatar_code,
       current_avatar: current_avatar,
       current_index: 0,
       current_skins: current_skins,
       current_skin: current_skin,
       current_user: user,
       sidebar_code: "tavern",
       skills: skills
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
