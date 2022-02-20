defmodule MobaWeb.ArenaSelectLiveView do
  use MobaWeb, :live_view

  def mount(_, %{"user_id" => user_id}, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)
    user = socket.assigns.current_user

    all_heroes = Game.eligible_heroes_for_pvp(user_id)

    mode = if Enum.find(all_heroes, &(&1.league_tier == Moba.max_league_tier())), do: "grandmaster", else: "master"
    mode_tier = if mode == "grandmaster", do: 6, else: 5

    mode_heroes = Enum.filter(all_heroes, &(&1.league_tier == mode_tier))

    skins =
      user
      |> Accounts.unlocked_codes_for()
      |> Game.list_skins_with_codes()

    selections =
      Enum.map(all_heroes, fn hero ->
        avatar_code = hero.avatar.code
        avatar_skins = [Game.default_skin(hero.avatar.code)] ++ Enum.filter(skins, &(&1.avatar_code == avatar_code))
        index = Enum.find_index(avatar_skins, fn skin -> skin.id == hero.skin_id end)

        %{
          hero_id: hero.id,
          index: index,
          skins: avatar_skins
        }
      end)

    cond do
      user.current_pvp_hero_id ->
        {:ok,
         socket
         |> push_redirect(to: "/arena")}

      length(all_heroes) == 0 ->
        {:ok,
         socket
         |> put_flash(:info, "You need to finish at least one hero before playing the Arena.")
         |> push_redirect(to: "/base")}

      Moba.restarting?() ->
        {:ok,
         socket
         |> put_flash(:info, "The new match is not ready yet, please wait a few minutes and try again")
         |> push_redirect(to: "/base")}

      true ->
        {:ok,
         assign(socket,
           all_heroes: all_heroes,
           heroes: mode_heroes,
           selections: selections,
           mode: mode
         )}
    end
  end

  def handle_event("select", %{"id" => id}, socket) do
    hero = Game.get_hero!(id)

    Moba.prepare_current_pvp_hero!(hero)

    {:noreply, socket |> redirect(to: "/game/pvp")}
  end

  def handle_event("switch-mode", _, socket) do
    current_mode = socket.assigns.mode

    new_mode = if current_mode == "master", do: "grandmaster", else: "master"
    mode_tier = if new_mode == "grandmaster", do: 6, else: 5
    mode_heroes = Enum.filter(socket.assigns.all_heroes, &(&1.league_tier == mode_tier))

    {:noreply, assign(socket, mode: new_mode, heroes: mode_heroes)}
  end

  def handle_event(
        "set-skin",
        %{"hero-id" => hero_id, "skin-code" => skin_code},
        %{assigns: %{heroes: heroes, selections: selections}} = socket
      ) do
    id = String.to_integer(hero_id)
    selection = Enum.find(selections, fn selection -> selection.hero_id == id end)
    skin = Enum.find(selection.skins, &(&1.code == skin_code))

    index = Enum.find_index(heroes, fn hero -> hero.id == id end)
    hero = Enum.find(heroes, fn hero -> hero.id == id end)

    updated_hero = Game.set_hero_skin!(hero, skin)
    updated_heroes = List.replace_at(heroes, index, updated_hero)

    skin_index = Enum.find_index(selection.skins, fn selection_skin -> selection_skin.code == skin_code end)
    updated_selection = %{selection | index: skin_index}

    updated_selections =
      Enum.map(selections, fn selection ->
        if selection.hero_id == updated_selection.hero_id do
          updated_selection
        else
          selection
        end
      end)

    {:noreply, assign(socket, heroes: updated_heroes, selections: updated_selections)}
  end

  def render(assigns) do
    MobaWeb.ArenaView.render("select.html", assigns)
  end
end
