defmodule MobaWeb.TavernLive do
  use MobaWeb, :live_view

  def mount(_, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    with socket = index_assigns(params, socket) do
      {:noreply, socket}
    end
  end

  def handle_event("show-avatars", _, socket) do
    {:noreply, assign(socket, active_tab: "avatars")}
  end

  def handle_event("show-skills", _, socket) do
    {:noreply, assign(socket, active_tab: "skills")}
  end

  def handle_event("show-skins", _, socket) do
    {:noreply, assign(socket, active_tab: "skins")}
  end

  def handle_event("previous-skin", _, socket) do
    with index = socket.assigns.current_index - 1,
         skin = Enum.at(socket.assigns.current_skins, index) do
      {:noreply, assign(socket, current_skin: skin, current_index: index)}
    end
  end

  def handle_event("next-skin", _, socket) do
    with index = socket.assigns.current_index + 1,
         skin = Enum.at(socket.assigns.current_skins, index) do
      {:noreply, assign(socket, current_skin: skin, current_index: index)}
    end
  end

  def handle_event("set-avatar", %{"code" => code}, %{assigns: %{all_avatars: all_avatars}} = socket) do
    with avatar = Enum.find(all_avatars, &(&1.code == code)),
         skins = Game.list_avatar_skins(code),
         skin = List.first(skins) do
      {:noreply, assign(socket, current_avatar: avatar, current_skins: skins, current_skin: skin, current_index: 0)}
    end
  end

  def handle_event("set-skin", %{"code" => code}, socket) do
    with skin = Enum.find(socket.assigns.current_skins, &(&1.code == code)) do
      {:noreply, assign(socket, current_skin: skin)}
    end
  end

  def handle_event("unlock-avatar", %{"code" => code}, %{assigns: %{current_user: user}} = socket) do
    with resource = Game.get_avatar_by_code!(code),
         user = Accounts.create_unlock!(user, resource) do
      {:noreply, assign(socket, current_user: user)}
    end
  end

  def handle_event("unlock-skill", %{"code" => code}, %{assigns: %{current_user: user}} = socket) do
    with resource = Game.get_current_skill!(code, 1),
         user = Accounts.create_unlock!(user, resource) do
      {:noreply, assign(socket, current_user: user)}
    end
  end

  def handle_event("unlock-skin", %{"code" => code}, %{assigns: %{current_user: user}} = socket) do
    with resource = Game.get_skin_by_code!(code),
         user = Accounts.create_unlock!(user, resource) do
      {:noreply, assign(socket, current_user: user)}
    end
  end

  def render(assigns) do
    MobaWeb.TavernView.render("index.html", assigns)
  end

  defp index_assigns(params, %{assigns: %{current_user: user}} = socket) do
    with avatar_code = Map.get(params, "avatar"),
         active_tab = if(avatar_code, do: "skins", else: "avatars"),
         avatars = Game.list_unlockable_avatars(),
         all_avatars = Game.list_avatars() |> Enum.sort_by(& &1.level_requirement, :desc),
         user = Accounts.get_user_with_unlocks!(user.id),
         skills = Game.list_unlockable_skills(),
         current_avatar = Enum.find(all_avatars, &(&1.code == avatar_code)) || List.first(all_avatars),
         current_skins = Game.list_avatar_skins(current_avatar.code),
         current_skin = List.first(current_skins) do
      assign(socket,
        active_tab: active_tab,
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
      )
    end
  end
end
