defmodule MobaWeb.HeroLive do
  use MobaWeb, :live_view

  def mount(_, _, socket) do
    with socket = socket_init(socket) do
      {:ok, socket}
    end
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    with hero = Game.get_hero!(id),
         ranking = Game.pve_ranking(200) do
      if connected?(socket) do
        Game.subscribe_to_hero(id)
        MobaWeb.subscribe("hero-ranking")
      end

      {:noreply,
       socket
       |> assign(hero: hero, ranking: ranking)
       |> owner_assigns()
       |> quest_assigns()}
    end
  end

  def handle_event(
        "set-skin",
        %{"skin-code" => skin_code},
        %{assigns: %{skin_selection: selection, hero: hero}} = socket
      ) do
    with skin = Enum.find(selection.skins, &(&1.code == skin_code)),
         updated_hero = Game.set_skin!(hero, skin),
         skin_index = Enum.find_index(selection.skins, &(&1.code == skin_code)),
         updated_selection = Map.put(selection, :index, skin_index) do
      {:noreply, assign(socket, hero: updated_hero, skin_selection: updated_selection)}
    end
  end

  def handle_info({"hero", %{id: id}}, socket) do
    {:noreply, assign(socket, hero: Game.get_hero!(id))}
  end

  def handle_info({"ranking", _}, %{assigns: %{hero: %{id: id}}} = socket) do
    with hero = Game.get_hero!(id),
         ranking = Game.pve_ranking(200) do
      {:noreply, assign(socket, ranking: ranking, hero: hero)}
    end
  end

  def render(assigns) do
    MobaWeb.HeroView.render("show.html", assigns)
  end

  defp owner_assigns(
         %{
           assigns: %{
             hero: %{player_id: player_id} = hero,
             current_player: %{id: current_player_id, user: user}
           }
         } = socket
       )
       when player_id == current_player_id and not is_nil(user) do
    with skins = Accounts.unlocked_codes_for(user) |> Game.list_skins_with_codes(),
         avatar_code = hero.avatar.code,
         avatar_skins = [Game.default_skin(avatar_code)] ++ Enum.filter(skins, &(&1.avatar_code == avatar_code)),
         skin_index = Enum.find_index(avatar_skins, &(&1.id == hero.skin_id)),
         skin_selection = %{index: skin_index, skins: avatar_skins} do
      assign(socket, skin_selection: skin_selection)
    end
  end

  defp owner_assigns(socket), do: socket

  defp quest_assigns(%{assigns: %{hero: %{id: hero_id} = hero, current_hero: %{id: current_hero_id}}} = socket)
       when hero_id == current_hero_id do
    with completed_quest = Game.last_completed_quest(hero) do
      assign(socket, completed_quest: completed_quest)
    end
  end

  defp quest_assigns(socket), do: socket

  defp socket_init(%{assigns: %{current_player: player}} = socket) do
    assign_new(socket, :current_hero, fn -> player.current_pve_hero end)
  end
end
