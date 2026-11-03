defmodule MobaWeb.V2.CreateLive do
  use MobaWeb, :v2_live_view

  def mount(_params, _session, %{assigns: %{current_player: player}} = socket) when not is_nil(player) do
    {:ok, socket_player_init(player.id, socket)}
  end

  def mount(_params, %{"cache_key" => cache_key}, socket) do
    {:ok, socket_guest_init(cache_key, socket)}
  end

  def mount(_params, _session, socket) do
    {:ok, socket_init(assign(socket, current_hero: nil, current_player: nil))}
  end

  def handle_event("filter", %{"role" => role}, %{assigns: %{all_avatars: all_avatars, filter: filter}} = socket) do
    filter = if filter == role || role == "", do: nil, else: role
    avatars = if filter, do: Enum.filter(all_avatars, &(&1.role == role)), else: all_avatars
    {:noreply, assign(socket, filter: filter, avatars: avatars)}
  end

  def handle_event("pick-avatar", %{"id" => id}, %{assigns: %{all_avatars: avatars}} = socket) do
    case Enum.find(avatars, &(to_string(&1.id) == to_string(id))) do
      nil -> {:noreply, socket}
      avatar -> {:noreply, select_avatar(socket, avatar)}
    end
  end

  def handle_event("repick-avatar", _, %{assigns: %{preview: true}} = socket), do: {:noreply, socket}

  def handle_event("repick-avatar", _, %{assigns: %{cache_key: cache_key}} = socket) do
    put_cache(cache_key, nil, [], nil)
    {:noreply, assign(socket, selected_avatar: nil, selected_skills: [], selected_build_index: nil)}
  end

  def handle_event(
        "pick-skill",
        %{"id" => id},
        %{assigns: %{custom: true, cache_key: cache_key, selected_avatar: selected_avatar} = assigns} = socket
      ) do
    skill = Enum.find(assigns.skills, &(to_string(&1.id) == to_string(id)))
    selected_skills = if skill, do: manage_skills(assigns.selected_skills, skill), else: assigns.selected_skills
    put_cache(cache_key, selected_avatar, selected_skills, nil)
    {:noreply, assign(socket, selected_skills: selected_skills, selected_build_index: nil)}
  end

  def handle_event("pick-skill", _, %{assigns: %{custom: false}} = socket), do: {:noreply, socket}

  def handle_event(
        "pick-build",
        %{"number" => index},
        %{assigns: %{cache_key: cache_key, selected_avatar: selected_avatar}} = socket
      ) do
    with true <- not is_nil(selected_avatar),
         {index, ""} when index >= 0 <- Integer.parse(to_string(index)),
         {selected_skills, _} <- Game.skill_build_for(selected_avatar.role, index) do
      put_cache(cache_key, selected_avatar, selected_skills, index)
      {:noreply, assign(socket, selected_skills: selected_skills, selected_build_index: index)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle-custom", _, %{assigns: %{custom: custom} = assigns} = socket) do
    if !custom && !is_nil(assigns.selected_build_index) do
      put_cache(assigns.cache_key, assigns.selected_avatar, [], nil)
      {:noreply, assign(socket, custom: true, selected_skills: [], selected_build_index: nil)}
    else
      {:noreply, assign(socket, custom: !custom)}
    end
  end

  def handle_event("randomize", _, %{assigns: %{avatars: avatars}} = socket) do
    case Enum.random(if avatars == [], do: [nil], else: avatars) do
      nil -> {:noreply, socket}
      avatar -> {:noreply, select_avatar(socket, avatar)}
    end
  end

  def handle_event(
        "create",
        %{"avatar" => avatar_id, "skills" => skill_ids, "name" => name},
        %{assigns: %{preview: true} = assigns} = socket
      ) do
    player = assigns.current_player
    avatar = Enum.find(assigns.all_avatars, &(to_string(&1.id) == avatar_id))
    allowed = MapSet.new(assigns.skills, &to_string(&1.id))

    cond do
      !is_map(player) || is_nil(Map.get(player, :id)) || is_nil(avatar) ||
        !is_list(skill_ids) || length(skill_ids) != 3 || length(Enum.uniq(skill_ids)) != 3 ||
          !Enum.all?(skill_ids, &(is_binary(&1) && MapSet.member?(allowed, &1))) ->
        {:reply, %{error: "Choose an unlocked hero and three unlocked skills."}, socket}

      !is_binary(name) ->
        {:reply, %{error: "Use 3–15 characters for your hero name."}, socket}

      player.user_id && validation_error(name, socket) ->
        {:reply, %{error: validation_error(name, socket)}, socket}

      true ->
        hero_name = if player.user_id, do: String.trim(name), else: avatar.name

        case Game.invoke_hero(player, %{name: hero_name}, avatar.id, skill_ids) do
          {:ok, _} ->
            {:reply, %{ok: true}, push_navigate(socket, to: preview_path(socket, "/training"))}

          {:error, _} ->
            {:reply, %{error: "Unable to create your hero. Choose three unlocked skills and try again."}, socket}
        end
    end
  end

  def handle_event(
        "create",
        _,
        %{assigns: %{current_player: player, selected_avatar: avatar, selected_skills: selected_skills, name: name}} =
          socket
      ) do
    if player && Map.get(player, :id) && avatar do
      hero_name = hero_name(player, avatar, name, socket)

      case Game.invoke_hero(player, %{name: hero_name}, avatar.id, Enum.map(selected_skills, & &1.id)) do
        {:ok, _} -> {:noreply, push_navigate(socket, to: preview_path(socket, "/training"))}
        {:error, _} -> {:noreply, assign(socket, error: "Choose an unlocked hero and three unlocked skills.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate", %{"name" => name}, socket) do
    {:noreply, assign(socket, error: validation_error(name, socket), name: name)}
  end

  defp select_avatar(%{assigns: assigns} = socket, avatar) do
    {skills, index} =
      if assigns.custom do
        {assigns.selected_skills, nil}
      else
        index = assigns.selected_build_index || 0
        {skills, _} = Game.skill_build_for(avatar.role, index)
        {skills, index}
      end

    put_cache(assigns.cache_key, avatar, skills, index)

    socket
    |> assign(selected_avatar: avatar, selected_skills: skills, selected_build_index: index, error: nil)
    |> set_name(avatar)
  end

  defp initial_selection(cache_key, avatars, skills) do
    cached = get_cache(cache_key)
    avatar = cached.selected_avatar && Enum.find(avatars, &(&1.id == cached.selected_avatar.id))
    skill_ids = MapSet.new(skills, & &1.id)

    if avatar && Enum.all?(cached.selected_skills, &MapSet.member?(skill_ids, &1.id)) do
      %{cached | selected_avatar: avatar}
    else
      avatar = Enum.find(avatars, &(&1.code == "juggernaut")) || List.first(avatars)
      {selected_skills, _} = Game.skill_build_for(avatar.role, 0)
      %{selected_avatar: avatar, selected_skills: selected_skills, selected_build_index: 0}
    end
  end

  defp add_skill(selected, skill) when length(selected) < 3, do: selected ++ [skill]
  defp add_skill(selected, _), do: selected
  defp remove_skill(selected, skill), do: selected -- [skill]

  defp get_cache(cache_key) do
    case Cachex.get(:game_cache, cache_key) do
      {:ok, nil} -> %{selected_avatar: nil, selected_skills: [], selected_build_index: nil}
      {:ok, attrs} -> attrs
    end
  end

  defp hero_name(%{user_id: nil}, avatar, _name, _socket), do: avatar.name

  defp hero_name(player, _avatar, name, socket) do
    if !is_nil(name) && is_nil(validation_error(name, socket)), do: name, else: player.user.username
  end

  defp manage_skills(selected_skills, skill) do
    if Enum.member?(selected_skills, skill),
      do: remove_skill(selected_skills, skill),
      else: add_skill(selected_skills, skill)
  end

  defp put_cache(cache_key, avatar, skills, selected_build_index) do
    Cachex.put(:game_cache, cache_key, %{
      selected_avatar: avatar,
      selected_skills: skills,
      selected_build_index: selected_build_index
    })
  end

  defp set_name(%{assigns: %{current_player: %{user_id: nil}}} = socket, avatar) when not is_nil(avatar),
    do: assign(socket, name: avatar.name)

  defp set_name(%{assigns: %{current_player: %{user: %{username: username}}}} = socket, _),
    do: assign(socket, name: username)

  defp set_name(socket, _), do: assign(socket, name: nil)

  defp socket_init(socket) do
    assign(socket,
      custom: false,
      error: nil,
      filter: nil,
      name: nil,
      sidebar_code: "training"
    )
  end

  defp socket_guest_init(cache_key, socket) do
    avatars = Game.list_creation_avatars()
    skills = Game.list_creation_skills(1)
    cached = initial_selection(cache_key, avatars, skills)

    socket
    |> socket_init()
    |> assign(
      all_avatars: avatars,
      avatars: avatars,
      cache_key: cache_key,
      current_hero: nil,
      current_player: %{hero_collection: [], user: nil, user_id: nil},
      custom: is_nil(cached.selected_build_index),
      selected_avatar: cached.selected_avatar,
      selected_skills: cached.selected_skills,
      selected_build_index: cached.selected_build_index,
      skills: skills
    )
    |> set_name(cached.selected_avatar)
  end

  defp socket_player_init(player_id, %{assigns: %{current_player: player}} = socket) do
    socket = socket_init(socket)
    unlocked_codes = unlocked_codes_for(player)
    avatars = Game.list_creation_avatars(unlocked_codes)
    collection_codes = Enum.map(player.hero_collection, & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))
    skills = Game.list_creation_skills(1, unlocked_codes)
    cached = initial_selection(player_id, avatars, skills)

    assign(socket,
      all_avatars: avatars,
      avatars: avatars,
      blank_collection: blank_collection,
      cache_key: player.id,
      custom: is_nil(cached.selected_build_index),
      selected_avatar: cached.selected_avatar,
      selected_skills: cached.selected_skills,
      selected_build_index: cached.selected_build_index,
      skills: skills
    )
    |> set_name(cached.selected_avatar)
  end

  defp unlocked_codes_for(%{user: user}) when not is_nil(user), do: Accounts.unlocked_codes_for(user)
  defp unlocked_codes_for(_), do: []

  defp validation_error(name, %{assigns: %{current_player: %{user: user}}}) do
    name = String.trim(name)
    length = String.length(name)

    if length >= 3 and length <= 15 do
      if name == user.username || is_nil(Accounts.get_user_by_username(name)), do: nil, else: "Name already taken."
    else
      "Invalid name size, minimum is 3 characters."
    end
  end
end
