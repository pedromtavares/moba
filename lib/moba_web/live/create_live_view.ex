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
       filter: nil,
       summoning?: false,
       error: nil,
       name: nil
     )}
  end

  def mount(_params, %{"summon" => true, "user_id" => user_id}, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)
    user = socket.assigns.current_user
    unlocked_codes = Accounts.unlocked_codes_for(user)
    cached = get_cache(user.id)
    avatars = Game.list_creation_avatars(unlocked_codes)
    items = Moba.cached_items()

    total_gold =
      Moba.summon_total_gold() - (Enum.map(cached.selected_items, &(&1 && Game.item_price(&1))) |> Enum.sum())

    {:ok,
     assign(socket,
       skills: Game.list_creation_skills(5, unlocked_codes),
       avatars: avatars,
       all_avatars: avatars,
       selected_avatar: cached.selected_avatar,
       selected_skills: cached.selected_skills,
       selected_items: cached.selected_items,
       custom: true,
       cache_key: user.id,
       filter: nil,
       summoning?: true,
       items: items,
       total_gold: total_gold,
       epic_items: Enum.filter(items, fn item -> item.rarity == "epic" end),
       legendary_items: Enum.filter(items, fn item -> item.rarity == "legendary" end),
       error: nil,
       name: nil
     )}
  end

  def mount(_params, %{"user_id" => user_id}, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)
    user = socket.assigns.current_user
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
       filter: nil,
       summoning?: false,
       error: nil,
       name: user.username
     )}
  end

  def handle_event("filter", %{"role" => role}, %{assigns: %{all_avatars: all_avatars, filter: filter}} = socket) do
    filter =
      if filter == role do
        nil
      else
        role
      end

    avatars =
      if filter do
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

  def handle_event("repick-avatar", _, %{assigns: %{cache_key: cache_key}} = socket) do
    put_cache(cache_key, nil, [], nil)

    {:noreply, assign(socket, selected_avatar: nil, selected_skills: [], selected_build_index: nil)}
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

  def handle_event("create-easy", _, socket), do: create_hero(true, socket)
  def handle_event("create-veteran", _, socket), do: create_hero(false, socket)

  def handle_event(
        "select-item",
        %{"code" => code},
        %{assigns: %{selected_skills: skills, cache_key: cache_key, selected_avatar: avatar} = assigns} = socket
      ) do
    item = get_item(code, socket)

    {items, gold} =
      if Enum.member?(assigns.selected_items, item) do
        remove_item(assigns, item)
      else
        add_item(assigns, item)
      end

    put_cache(cache_key, avatar, skills, nil, items)

    {:noreply, assign(socket, selected_items: items, total_gold: gold)}
  end

  def handle_event(
        "summon",
        _,
        %{
          assigns: %{
            current_user: user,
            selected_avatar: avatar,
            selected_skills: selected_skills,
            selected_items: selected_items
          }
        } = socket
      ) do
    skills =
      selected_skills
      |> Enum.map(fn skill -> skill.id end)
      |> Game.list_chosen_skills()

    Game.summon_hero!(user, avatar, skills, selected_items)

    delete_cache(socket)

    {:noreply, socket |> redirect(to: "/base")}
  end

  def handle_event("validate", %{"name" => name}, socket) do
    {:noreply, assign(socket, error: validation_error(name, socket), name: name)}
  end

  def render(assigns) do
    MobaWeb.CreateView.render("index.html", assigns)
  end

  defp create_hero(
         easy_mode,
         %{assigns: %{current_user: user, selected_avatar: avatar, selected_skills: selected_skills, name: name}} =
           socket
       ) do
    skills =
      selected_skills
      |> Enum.map(fn skill -> skill.id end)
      |> Game.list_chosen_skills()

    hero_name = if !is_nil(name) && is_nil(validation_error(name, socket)), do: name, else: user.username

    Moba.create_current_pve_hero!(%{name: hero_name, easy_mode: easy_mode}, user, avatar, skills)

    delete_cache(socket)

    {:noreply, socket |> redirect(to: "/game/pve")}
  end

  defp add_skill(selected, skill) when length(selected) < 3 do
    selected ++ [skill]
  end

  defp add_skill(selected, _), do: selected

  defp remove_skill(selected, skill) do
    selected -- [skill]
  end

  defp add_item(%{selected_items: selected, total_gold: total_gold}, item) when length(selected) < 6 do
    price = Game.item_price(item)

    if total_gold >= price do
      {selected ++ [item], total_gold - price}
    else
      {selected, total_gold}
    end
  end

  defp add_item(%{selected_items: selected, total_gold: total_gold}, _), do: {selected, total_gold}

  defp remove_item(%{selected_items: selected, total_gold: total_gold}, item) do
    {selected -- [item], total_gold + Game.item_price(item)}
  end

  defp get_cache(cache_key) do
    case Cachex.get(:game_cache, cache_key) do
      {:ok, nil} -> %{selected_avatar: nil, selected_skills: [], selected_build_index: nil, selected_items: []}
      {:ok, attrs} -> attrs
    end
  end

  defp put_cache(cache_key, avatar, skills, selected_build_index, selected_items \\ []) do
    Cachex.put(:game_cache, cache_key, %{
      selected_avatar: avatar,
      selected_skills: skills,
      selected_build_index: selected_build_index,
      selected_items: selected_items
    })
  end

  defp delete_cache(%{assigns: %{cache_key: key}}), do: Cachex.del(:game_cache, key)

  defp get_item(code, socket), do: Enum.find(socket.assigns.items, fn item -> item.code == code end)

  defp validation_error(name, %{assigns: %{current_user: user}}) do
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
