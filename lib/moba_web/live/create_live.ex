defmodule MobaWeb.CreateLive do
  use MobaWeb, :live_view

  def mount(_params, %{"token" => token, "cache_key" => cache_key}, socket) do
    with socket = socket_guest_init(token, cache_key, socket) do
      {:ok, socket}
    end
  end

  def mount(_params, %{"player_id" => player_id}, socket) do
    with socket = socket_player_init(player_id, socket) do
      {:ok, socket}
    end
  end

  def handle_event("filter", %{"role" => role}, %{assigns: %{all_avatars: all_avatars, filter: filter}} = socket) do
    with filter = if(filter == role, do: nil, else: role),
         avatars = if(filter, do: Enum.filter(all_avatars, &(&1.role == role)), else: all_avatars) do
      {:noreply, assign(socket, filter: filter, avatars: avatars)}
    end
  end

  def handle_event("pick-avatar", %{"id" => id}, %{assigns: %{cache_key: cache_key}} = socket) do
    with avatar = Game.get_avatar!(id) do
      put_cache(cache_key, avatar, [], nil)

      {:noreply,
       assign(socket,
         selected_avatar: avatar,
         selected_skills: [],
         selected_build_index: nil
       )
       |> set_name(avatar)}
    end
  end

  def handle_event("repick-avatar", _, %{assigns: %{cache_key: cache_key}} = socket) do
    put_cache(cache_key, nil, [], nil)

    {:noreply, assign(socket, selected_avatar: nil, selected_skills: [], selected_build_index: nil)}
  end

  def handle_event(
        "pick-skill",
        %{"id" => id},
        %{assigns: %{custom: true, cache_key: cache_key, selected_avatar: selected_avatar} = assigns} = socket
      ) do
    with skill = Game.get_skill!(id),
         selected_skills = manage_skills(assigns.selected_skills, skill) do
      put_cache(cache_key, selected_avatar, selected_skills, nil)

      {:noreply, assign(socket, selected_skills: selected_skills, selected_build_index: nil)}
    end
  end

  def handle_event("pick-skill", _, %{assigns: %{custom: false}} = socket), do: {:noreply, socket}

  def handle_event(
        "pick-build",
        %{"number" => index},
        %{assigns: %{cache_key: cache_key, selected_avatar: selected_avatar}} = socket
      ) do
    with index = String.to_integer(index),
         selected_skills = Game.skill_build_for(selected_avatar.role, index) |> elem(0) do
      put_cache(cache_key, selected_avatar, selected_skills, index)

      {:noreply, assign(socket, selected_skills: selected_skills, selected_build_index: index)}
    end
  end

  def handle_event("toggle-custom", _, %{assigns: %{custom: custom}} = socket) do
    {:noreply, assign(socket, custom: !custom)}
  end

  def handle_event("randomize", _, %{assigns: %{cache_key: cache_key, avatars: avatars}} = socket) do
    with selected_avatar = Enum.shuffle(avatars) |> List.first() do
      put_cache(cache_key, selected_avatar, [], nil)

      {:noreply, assign(socket, selected_avatar: selected_avatar, selected_skills: []) |> set_name(selected_avatar)}
    end
  end

  def handle_event(
        "create",
        _,
        %{assigns: %{current_player: player, selected_avatar: avatar, selected_skills: selected_skills, name: name}} =
          socket
      ) do
    with skills = Enum.map(selected_skills, & &1.id) |> Game.list_chosen_skills(),
         hero_name = hero_name(player, avatar, name, socket) do
      Game.create_current_pve_hero!(%{name: hero_name}, player, avatar, skills)

      {:noreply, socket |> redirect(to: "/training")}
    end
  end

  def handle_event("validate", %{"name" => name}, socket) do
    with error = validation_error(name, socket) do
      {:noreply, assign(socket, error: error, name: name)}
    end
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

  defp get_cache(cache_key) do
    case Cachex.get(:game_cache, cache_key) do
      {:ok, nil} -> %{selected_avatar: nil, selected_skills: [], selected_build_index: nil}
      {:ok, attrs} -> attrs
    end
  end

  defp hero_name(player, avatar, name, socket) do
    cond do
      is_nil(player.user_id) -> avatar.name
      !is_nil(name) && is_nil(validation_error(name, socket)) -> name
      true -> player.user.username
    end
  end

  defp manage_skills(selected_skills, skill) do
    if Enum.member?(selected_skills, skill) do
      remove_skill(selected_skills, skill)
    else
      add_skill(selected_skills, skill)
    end
  end

  defp put_cache(cache_key, avatar, skills, selected_build_index) do
    Cachex.put(:game_cache, cache_key, %{
      selected_avatar: avatar,
      selected_skills: skills,
      selected_build_index: selected_build_index
    })
  end

  defp set_name(%{assigns: %{current_player: %{user_id: user_id}}} = socket, avatar)
       when is_nil(user_id) and not is_nil(avatar) do
    assign(socket, name: avatar.name)
  end

  defp set_name(%{assigns: %{current_player: %{user: %{username: username}}}} = socket, _) do
    assign(socket, name: username)
  end

  defp set_name(socket, _), do: assign(socket, name: nil)

  defp socket_init(socket) do
    assign(socket, custom: false, error: nil, filter: nil, name: nil)
  end

  defp socket_guest_init(token, cache_key, socket) do
    with socket = socket_init(socket),
         cached = get_cache(cache_key),
         avatars = Game.list_creation_avatars(),
         skills = Game.list_creation_skills(1) do
      assign(socket,
        all_avatars: avatars,
        avatars: avatars,
        cache_key: cache_key,
        current_player: nil,
        selected_avatar: cached.selected_avatar,
        selected_skills: cached.selected_skills,
        selected_build_index: cached.selected_build_index,
        skills: skills,
        token: token
      )
    end
  end

  defp socket_player_init(player_id, %{assigns: %{current_player: player}} = socket) do
    with socket = socket_init(socket),
         unlocked_codes = unlocked_codes_for(player),
         cached = get_cache(player_id),
         avatars = Game.list_creation_avatars(unlocked_codes),
         collection_codes = Enum.map(player.hero_collection, & &1["code"]),
         blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes)),
         skills = Game.list_creation_skills(1, unlocked_codes) do
      assign(socket,
        all_avatars: avatars,
        avatars: avatars,
        blank_collection: blank_collection,
        cache_key: player.id,
        selected_avatar: cached.selected_avatar,
        selected_skills: cached.selected_skills,
        selected_build_index: cached.selected_build_index,
        skills: skills
      )
      |> set_name(cached.selected_avatar)
    end
  end

  def unlocked_codes_for(%{user: user}) when not is_nil(user) do
    Accounts.unlocked_codes_for(user)
  end

  def unlocked_codes_for(_), do: []

  defp validation_error(name, %{assigns: %{current_player: %{user: user}}}) do
    length = String.length(name)

    if length >= 3 and length <= 15 do
      if name == user.username || is_nil(Accounts.get_user_by_username(name)) do
        nil
      else
        "Name already taken."
      end
    else
      "Invalid name size, minimum is 3 characters."
    end
  end
end
