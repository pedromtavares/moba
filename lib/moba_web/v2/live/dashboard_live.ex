defmodule MobaWeb.V2.DashboardLive do
  use MobaWeb, :v2_live_view

  @base_hero_count Moba.base_hero_count()

  def mount(_params, _session, socket) do
    %{assigns: %{current_player: player}} = socket
    {:ok, socket_init(socket, player)}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    %{assigns: %{all_heroes: all_heroes, loaded: loaded}} = socket

    visible =
      case filter do
        "finished" -> Enum.filter(all_heroes, & &1.finished_at)
        "unfinished" -> Enum.filter(all_heroes, &is_nil(&1.finished_at))
        _ -> all_heroes
      end

    loaded = if length(visible) < @base_hero_count, do: Enum.uniq(loaded ++ [filter]), else: loaded

    {:noreply, assign(socket, visible_heroes: visible, filter: filter, loaded: loaded)}
  end

  def handle_event("load-all", _, socket) do
    %{assigns: %{filter: filter, current_player: player, all_heroes: all_heroes, loaded: loaded}} = socket

    visible =
      if filter == "finished",
        do: Game.list_all_finished_heroes(player.id),
        else: Game.list_all_unfinished_heroes(player.id)

    all_heroes = Enum.uniq(all_heroes ++ visible)

    {:noreply,
     assign(socket,
       visible_heroes: visible,
       all_heroes: all_heroes,
       loaded: Enum.uniq(loaded ++ [filter])
     )}
  end

  def handle_event("toggle-rewards", _, socket) do
    {:noreply, assign(socket, show_rewards: !socket.assigns.show_rewards)}
  end

  def handle_event("continue", %{"id" => id}, socket) do
    %{assigns: %{current_player: player}} = socket
    hero = Game.get_hero!(id)

    if hero.player_id == player.id do
      player = Game.set_current_pve_hero!(player, id)

      {:noreply,
       socket
       |> assign(current_hero: hero, current_player: player)
       |> redirect(to: "/training")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("archive", %{"id" => id}, socket) do
    %{assigns: %{current_player: player, current_hero: current_hero}} = socket
    hero = Game.get_hero!(id)

    if hero.player_id == player.id do
      Game.archive_hero!(hero)
      if hero.finished_at, do: Game.update_hero_collection!(hero)

      current_hero = if current_hero && hero.id == current_hero.id, do: nil, else: current_hero

      {:noreply,
       assign(socket,
         current_hero: current_hero,
         visible_heroes: Enum.reject(socket.assigns.visible_heroes, &(&1.id == hero.id)),
         all_heroes: Enum.reject(socket.assigns.all_heroes, &(&1.id == hero.id))
       )}
    else
      {:noreply, socket}
    end
  end

  # Private functions

  defp socket_init(socket, player) do
    unfinished = Game.latest_unfinished_heroes(player.id)
    finished = Game.latest_finished_heroes(player.id)
    all_heroes = unfinished ++ finished
    collection_codes = Enum.map(player.hero_collection || [], & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))
    filter = if Enum.any?(unfinished), do: "unfinished", else: "finished"
    visible = if filter == "unfinished", do: unfinished, else: finished
    loaded = if length(visible) < @base_hero_count, do: [filter], else: []

    assign(socket,
      sidebar_code: "base",
      all_heroes: all_heroes,
      visible_heroes: visible,
      filter: filter,
      loaded: loaded,
      blank_collection: blank_collection,
      collection_codes: collection_codes,
      hero_count: length(all_heroes),
      next_pve_tier: next_pve_tier(player),
      show_rewards: false
    )
  end

  @max_pve_tier Moba.max_pve_tier()

  defp next_pve_tier(%{pve_tier: tier}) when tier >= @max_pve_tier, do: nil
  defp next_pve_tier(%{pve_tier: tier}), do: tier + 1

  defp current_quest_description(%{pve_tier: tier}), do: Game.get_quest(tier + 1).description

  defp quest_progression_pct(%{pve_progression: nil}), do: 0

  defp quest_progression_pct(%{pve_tier: tier, pve_progression: progression}) do
    quest = Game.get_quest(tier + 1)
    codes = Map.get(progression, quest.field, [])
    trunc(length(codes) * 100 / quest.goal)
  end

  defp quest_progression_label(%{pve_progression: nil}), do: "0/? Avatars"

  defp quest_progression_label(%{pve_tier: tier, pve_progression: progression}) do
    quest = Game.get_quest(tier + 1)
    codes = Map.get(progression, quest.field, [])
    "#{length(codes)}/#{quest.goal} Avatars"
  end

  defp quest_avatars_title(%{pve_progression: nil}), do: "Already trained: none"

  defp quest_avatars_title(%{pve_tier: tier, pve_progression: progression}) do
    quest = Game.get_quest(tier + 1)
    codes = Map.get(progression, quest.field, [])
    names = Enum.map(codes, &(Moba.load_resource(&1).name))
    "Already trained: " <> Enum.join(names, ", ")
  end

  defp can_delete_hero?(hero) do
    is_nil(hero.pve_ranking) ||
      hero.league_tier < Moba.max_league_tier() ||
      is_nil(hero.finished_at) ||
      not Game.available_hero?(hero)
  end

  defp all_loaded?(loaded, filter), do: filter in loaded

  @max_total_farm Moba.max_total_farm()

  defp collection_avatar_class(%{"total_farm" => farm}) when farm == @max_total_farm, do: "ring-2 ring-gold"
  defp collection_avatar_class(_), do: ""

  defp training_difficulty_for(tier) do
    Map.get(Game.get_quest(tier), :difficulty) || Game.get_quest(7).difficulty
  end

  defp training_bonus_for(tier), do: Map.get(Game.get_quest(tier), :training_bonus)

  defp max_league_allowed_for(tier) do
    Map.get(Game.get_quest(tier), :max_league) || Game.get_quest(7).max_league
  end

  defp quest_shard_prize(tier), do: Game.get_quest(tier).prize
end
