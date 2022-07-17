defmodule MobaWeb.UserLive do
  use MobaWeb, :live_view

  def mount(_, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    with socket = user_assigns(id, nil, socket) do
      if connected?(socket), do: MobaWeb.subscribe("player-ranking")
      {:noreply, socket}
    end
  end

  def handle_params(%{"player_id" => id}, _uri, socket) do
    with %{user_id: user_id} = player <- Game.get_player!(id),
         socket = user_assigns(user_id, player, socket) do
      if connected?(socket), do: MobaWeb.subscribe("player-ranking")
      {:noreply, socket}
    end
  end

  def handle_event("set-featured", %{"id" => id}, socket) do
    with featured = Game.get_hero!(id) do
      {:noreply, assign(socket, featured: featured)}
    end
  end

  def handle_info({"ranking", _}, %{assigns: %{player: %{id: id}}} = socket) do
    with player = Game.get_player!(id),
         ranking = ranking_for(player) do
      {:noreply, assign(socket, ranking: ranking, player: player)}
    end
  end

  def render(assigns) do
    MobaWeb.UserView.render("show.html", assigns)
  end

  defp featured_hero(%{hero_collection: collection}) when length(collection) > 0 do
    hero = List.first(collection)
    Game.get_hero!(hero["hero_id"])
  end

  defp featured_hero(player), do: player.current_pve_hero

  defp ranking_for(%{bot_options: options}) when not is_nil(options), do: Game.bot_ranking()
  defp ranking_for(_), do: Game.player_ranking(50)

  defp user_assigns(user_id, cached_player, %{assigns: %{current_player: current_player}} = socket) do
    with user = Accounts.get_user!(user_id),
         player = cached_player || Moba.player_for(user),
         collection_codes = Enum.map(player.hero_collection, & &1["code"]),
         blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes)),
         duels = Game.list_finished_duels(player),
         featured = featured_hero(player),
         ranking = ranking_for(player),
         sidebar_code = if(player.id == current_player.id, do: "user", else: nil) do
      assign(socket,
        blank_collection: blank_collection,
        duels: duels,
        featured: featured,
        player: player,
        ranking: ranking,
        sidebar_code: sidebar_code,
        user: user
      )
    end
  end
end
