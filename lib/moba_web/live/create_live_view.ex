defmodule MobaWeb.CreateLiveView do
  use MobaWeb, :live_view

  def mount(_params, %{"token" => token, "cache_key" => cache_key}, socket) do
    cached = get_cache(cache_key)
    avatars = Game.list_creation_avatars()

    {:ok,
     assign(socket,
       skills: Game.list_creation_skills(1),
       avatars: avatars,
       all_avatars: avatars,
       custom: false,
       selected_avatar: cached.selected_avatar,
       selected_skills: cached.selected_skills,
       selected_build_index: cached.selected_build_index,
       current_user: nil,
       cache_key: cache_key,
       token: token,
       filter: nil
     )}
  end

  def mount(_params, %{"user_id" => user_id}, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)
    user = socket.assigns.current_user
    cond do
      Game.can_create_new_hero?(user) ->
        unlocked_codes = Accounts.unlocked_codes_for(user)
        cached = get_cache(user.id)
        avatars = Game.list_creation_avatars(unlocked_codes)

        {:ok,
         assign(socket,
           skills: Game.list_creation_skills(1, unlocked_codes),
           avatars: avatars,
           all_avatars: avatars,
           selected_avatar: cached.selected_avatar,
           selected_skills: cached.selected_skills,
           selected_build_index: cached.selected_build_index,
           custom: false,
           cache_key: user.id,
           filter: nil
         )}

      user.current_pvp_hero_id ->
        {:ok,
         socket
         |> redirect(to: "/game/pvp")}

      true ->
        {:ok,
         socket
         |> put_flash(:info, "The new match is not ready yet, please wait a few minutes and try again")
         |> push_redirect(to: "/match")}
    end
  end

  def handle_event("filter", %{"role" => role}, %{assigns: %{all_avatars: all_avatars, filter: filter}} = socket) do

    filter = if filter == role do
      nil
    else
      role
    end

    avatars = if filter do
      Enum.filter(all_avatars, &(&1.role == role))
    else
      all_avatars
    end

    {:noreply, assign(socket, filter: filter, avatars: avatars)}
  end

  def handle_event("pick-avatar", %{"id" => id}, %{assigns: %{cache_key: cache_key}} = socket) do
    avatar = Game.get_avatar!(id)

    put_cache(cache_key, avatar, [], nil)

    {:noreply, assign(socket, selected_avatar: avatar, selected_skills: [], selected_build_index: nil)}
  end

  def handle_event(
        "pick-skill",
        %{"id" => id},
        %{assigns: %{custom: custom, cache_key: cache_key, selected_avatar: selected_avatar} = assigns} = socket
      )
      when custom == true do
    skill = Game.get_skill!(id)

    selected_skills =
      if Enum.member?(assigns.selected_skills, skill) do
        remove_skill(assigns.selected_skills, skill)
      else
        add_skill(assigns.selected_skills, skill)
      end

    put_cache(cache_key, selected_avatar, selected_skills, nil)

    {:noreply, assign(socket, selected_skills: selected_skills, selected_build_index: nil)}
  end

  def handle_event("pick-skill", _, %{assigns: %{custom: custom}} = socket) when custom == false do
    {:noreply, socket}
  end

  def handle_event(
        "pick-build",
        %{"number" => index},
        %{assigns: %{cache_key: cache_key, selected_avatar: selected_avatar}} = socket
      ) do
    index = String.to_integer(index)
    selected_skills = Game.skill_build_for(selected_avatar.role, index) |> elem(0)

    put_cache(cache_key, selected_avatar, selected_skills, index)

    {:noreply, assign(socket, selected_skills: selected_skills, selected_build_index: index)}
  end

  def handle_event("toggle-custom", _, %{assigns: %{custom: custom}} = socket) do
    {:noreply, assign(socket, custom: !custom)}
  end

  def handle_event("randomize", _, %{assigns: %{cache_key: cache_key, avatars: avatars}} = socket) do
    selected_avatar =
      avatars
      |> Enum.shuffle()
      |> List.first()

    put_cache(cache_key, selected_avatar, [], nil)

    {:noreply, assign(socket, selected_avatar: selected_avatar, selected_skills: [])}
  end

  def handle_event(
        "create",
        _,
        %{assigns: %{current_user: user, selected_avatar: avatar, selected_skills: selected_skills}} = socket
      ) do
    skills =
      selected_skills
      |> Enum.map(fn skill -> skill.id end)
      |> Game.list_chosen_skills()

    name = if user.is_guest, do: avatar.name, else: user.username

    Moba.create_current_pve_hero!(%{name: name}, user, avatar, skills)

    delete_cache(socket)

    {:noreply, socket |> redirect(to: "/game/pve")}
  end

  def render(assigns) do
    MobaWeb.CreateView.render("index.html", assigns)
  end

  defp add_skill(selected, skill) when length(selected) < 3 do
    selected ++ [skill]
  end

  defp add_skill(selected, _), do: selected

  defp remove_skill(selected, skill) do
    selected -- [skill]
  end

  def get_cache(cache_key) do
    case Cachex.get(:game_cache, cache_key) do
      {:ok, nil} -> %{selected_avatar: nil, selected_skills: [], selected_build_index: nil}
      {:ok, attrs} -> attrs
    end
  end

  def put_cache(cache_key, avatar, skills, selected_build_index) do
    Cachex.put(:game_cache, cache_key, %{
      selected_avatar: avatar,
      selected_skills: skills,
      selected_build_index: selected_build_index
    })
  end

  def delete_cache(%{assigns: %{cache_key: key}}) do
    Cachex.del(:game_cache, key)
  end
end
