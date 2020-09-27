defmodule MobaWeb.ArenaSelectLiveView do
  use Phoenix.LiveView

  alias MobaWeb.ArenaView
  alias Moba.{Accounts, Game}

  def mount(_, %{"user_id" => user_id}, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)

    heroes = Game.eligible_heroes_for_pvp(user_id)

    user = socket.assigns.current_user

    cond do
      !Game.current_match().last_server_update_at ->
        {:ok,
         socket
         |> put_flash(:info, "The new match is not ready yet, please wait a few minutes and try again")
         |> push_redirect(to: "/match")}

      user.current_pvp_hero_id ->
        {:ok,
         socket
         |> push_redirect(to: "/arena")}

      true ->
        {:ok,
         assign(socket,
           heroes: heroes,
           hide_join_new_match_button: true
         )}
    end
  end

  def handle_event("select", %{"id" => id}, socket) do
    hero = Game.get_hero!(id)

    Moba.prepare_current_pvp_hero!(hero)

    {:noreply, socket |> redirect(to: "/game/pvp")}
  end

  def handle_event("switch-build", %{"id" => hero_id}, %{assigns: %{heroes: heroes}} = socket) do
    id = String.to_integer(hero_id)
    index = Enum.find_index(heroes, fn hero -> hero.id == id end)
    hero = Enum.find(heroes, fn hero -> hero.id == id end)
    updated = List.replace_at(heroes, index, Game.switch_build!(hero))

    {:noreply, assign(socket, heroes: updated)}
  end

  def render(assigns) do
    ArenaView.render("select.html", assigns)
  end
end
