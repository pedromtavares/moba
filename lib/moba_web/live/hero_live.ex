defmodule MobaWeb.HeroLive do
  use MobaWeb, :live_view

  def mount(_, _, socket) do
    with socket = socket_init(socket) do
      {:ok, socket}
    end
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    with hero = Game.get_hero!(id),
         ranking = Game.pve_search(hero) do
      if connected?(socket) do
        Game.subscribe_to_hero(id)
        MobaWeb.subscribe("hero-ranking")
      end

      {:noreply,
       socket
       |> assign(hero: hero, ranking: ranking)
       |> owner_assigns()
       |> progressions_assigns()}
    end
  end

  def handle_event("tab-display", %{"display" => display}, socket) do
    {:noreply, assign(socket, tab_display: display)}
  end

  def handle_event(
        "set-skin",
        %{"skin-code" => skin_code},
        %{assigns: %{skin_selection: selection, hero: hero}} = socket
      ) do
    with skin = Enum.find(selection.skins, &(&1.code == skin_code)),
         updated_hero = Game.set_hero_skin!(hero, skin),
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
         ranking = Game.pve_search(hero) do
      {:noreply, assign(socket, ranking: ranking, hero: hero)}
    end
  end

  def render(assigns) do
    MobaWeb.HeroView.render("show.html", assigns)
  end

  defp owner_assigns(
         %{assigns: %{hero: %{user_id: user_id} = hero, current_user: %{id: current_user_id} = user}} = socket
       )
       when user_id == current_user_id do
    with socket = progressions_assigns(socket),
         skins = Accounts.unlocked_codes_for(user) |> Game.list_skins_with_codes(),
         avatar_code = hero.avatar.code,
         avatar_skins = [Game.default_skin(avatar_code)] ++ Enum.filter(skins, &(&1.avatar_code == avatar_code)),
         skin_index = Enum.find_index(avatar_skins, &(&1.id == hero.skin_id)),
         skin_selection = %{index: skin_index, skins: avatar_skins} do
      assign(socket, skin_selection: skin_selection)
    end
  end

  defp owner_assigns(socket), do: socket

  defp progressions_assigns(%{assigns: %{hero: %{id: hero_id} = hero, current_hero: %{id: current_hero_id}}} = socket)
       when hero_id == current_hero_id do
    with completed_progressions = Game.last_completed_quest_progressions(hero),
         quest_codes = Moba.season_quest_codes(),
         completed_season_progression = Enum.find(completed_progressions, &Enum.member?(quest_codes, &1.quest.code)),
         completed_daily_progressions = Enum.filter(completed_progressions, & &1.quest.daily),
         tab_display = tab_display_priority(completed_season_progression) do
      assign(socket,
        completed_progressions: completed_progressions,
        completed_season_progression: completed_season_progression,
        completed_daily_progressions: completed_daily_progressions,
        tab_display: tab_display
      )
    end
  end

  defp progressions_assigns(socket), do: socket

  defp socket_init(%{assigns: %{current_user: current_user}} = socket) do
    assign_new(socket, :current_hero, fn -> Game.current_pve_hero(current_user) end)
  end

  defp tab_display_priority(season) when not is_nil(season), do: "season"
  defp tab_display_priority(_), do: "daily"
end
