defmodule MobaWeb.V2.DashboardLive do
  use MobaWeb, :v2_live_view

  import MobaWeb.V2.Components.ProgressionComponents
  import MobaWeb.CoreComponents, only: [icon: 1]

  embed_templates "dashboard_live/*"

  @base_hero_count Moba.base_hero_count()

  def mount(_params, _session, socket) do
    %{assigns: %{current_player: player}} = socket

    socket = socket |> assign(:current_scope, Game.TeamRuns.scope(player)) |> socket_init(player)

    {:ok, socket}
  end

  def handle_event("show-finished", _, socket), do: {:noreply, filter_training(socket, "finished")}
  def handle_event("show-unfinished", _, socket), do: {:noreply, filter_training(socket, "unfinished")}

  def handle_event("load-all", _, socket) do
    %{filter: filter, current_player: player} = socket.assigns
    heroes = Game.Heroes.list_solo_training(socket.assigns.current_scope, filter, 100)
    teams = training_teams(player, filter, 100)

    {:noreply,
     socket
     |> assign(
       all_heroes: Enum.uniq_by(socket.assigns.all_heroes ++ heroes, & &1.id),
       all_teams: Enum.uniq_by(socket.assigns.all_teams ++ teams, & &1.id),
       loaded: Enum.uniq(socket.assigns.loaded ++ [filter])
     )
     |> filter_training(filter)}
  end

  def handle_event("continue", %{"id" => id}, socket) do
    %{assigns: %{current_player: player}} = socket
    hero = Game.get_hero!(id)

    if hero.player_id == player.id do
      player = Game.set_current_pve_hero!(player, id)

      {:noreply,
       socket
       |> assign(current_hero: hero, current_player: player)
       |> push_navigate(
         to: preview_path(socket, if(socket.assigns.has_active_team, do: "/training?solo=true", else: "/training"))
       )}
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

  def handle_event("archive-team", %{"id" => id}, socket) do
    case Game.TeamRuns.archive(socket.assigns.current_scope, id) do
      {:ok, team} ->
        {:noreply,
         assign(socket,
           visible_teams: Enum.reject(socket.assigns.visible_teams, &(&1.id == team.id)),
           all_teams: Enum.reject(socket.assigns.all_teams, &(&1.id == team.id)),
           hero_count: socket.assigns.hero_count - 1,
           has_active_team:
             not is_nil(Game.TeamRuns.active(socket.assigns.current_scope, socket.assigns.current_player.id))
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Private functions

  defp socket_init(socket, player) do
    unfinished = Game.Heroes.list_solo_training(socket.assigns.current_scope, "unfinished")
    finished = Game.Heroes.list_solo_training(socket.assigns.current_scope, "finished")
    unfinished_teams = training_teams(player, "unfinished", @base_hero_count)
    finished_teams = training_teams(player, "finished", @base_hero_count)
    all_teams = unfinished_teams ++ finished_teams
    all_heroes = unfinished ++ finished
    collection_codes = Enum.map(player.hero_collection || [], & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))
    filter = if unfinished != [] || unfinished_teams != [], do: "unfinished", else: "finished"
    visible = if filter == "unfinished", do: unfinished, else: finished
    teams = if filter == "unfinished", do: unfinished_teams, else: finished_teams
    loaded = if length(visible) < @base_hero_count && length(teams) < @base_hero_count, do: [filter], else: []
    register_to_train = is_nil(player.user_id) && (finished != [] || finished_teams != [])

    assign(socket,
      sidebar_code: "base",
      register_to_train: register_to_train,
      guide_training_cta:
        register_to_train ||
          (player.user_id != nil && Phoenix.Flash.get(socket.assigns.flash, :training_registered) != nil),
      all_heroes: all_heroes,
      all_teams: all_teams,
      visible_teams: teams,
      has_active_team: unfinished_teams != [],
      visible_heroes: visible,
      filter: filter,
      loaded: loaded,
      blank_collection: blank_collection,
      collection_codes: collection_codes,
      hero_count: length(all_heroes) + length(all_teams)
    )
  end

  defp training_cta_path(%{register_to_train: true}), do: ~p"/users/register?from=training"
  defp training_cta_path(_assigns), do: ~p"/new"

  defp training_cta_label(true), do: "Register to continue training"
  defp training_cta_label(false), do: "Start training"

  defp filter_training(socket, filter) do
    heroes = Enum.filter(socket.assigns.all_heroes, &(is_nil(&1.finished_at) == (filter == "unfinished")))
    teams = Enum.filter(socket.assigns.all_teams, &(is_nil(&1.finished_at) == (filter == "unfinished")))

    loaded =
      if length(heroes) < @base_hero_count && length(teams) < @base_hero_count,
        do: Enum.uniq(socket.assigns.loaded ++ [filter]),
        else: socket.assigns.loaded

    assign(socket, visible_heroes: heroes, visible_teams: teams, filter: filter, loaded: loaded)
  end

  defp training_teams(player, filter, limit) do
    Game.TeamRuns.list_training(Game.TeamRuns.scope(player), player.id, filter, limit)
    |> Enum.flat_map(fn record ->
      with {:ok, run} <- Game.TeamRuns.read_state(record) do
        heroes = Game.TeamTraining.team(run) |> Enum.map(& &1.hero)

        [
          %{
            id: record.id,
            name: record.name,
            heroes: heroes,
            league_tier: run.league_tier,
            reward_mode: run.reward_mode,
            avg_farm: div(Enum.sum(Enum.map(heroes, &(&1.total_gold_farm + &1.total_xp_farm))), length(heroes)),
            turns_left: run.turns_left + run.reserve_turns,
            finished_at: record.finished_at,
            duration_seconds: record.duration_seconds
          }
        ]
      else
        {:error, :invalid_snapshot} -> []
      end
    end)
  end

  @max_pve_tier Moba.max_pve_tier()

  defp next_pve_tier(%{pve_tier: tier}) when tier >= @max_pve_tier, do: nil
  defp next_pve_tier(%{pve_tier: tier}), do: tier + 1

  defp current_quest_description(%{pve_tier: tier}), do: Game.get_quest(tier + 1).description

  defp quest_progression_pct(player) do
    {count, goal} = quest_progress(player)
    div(count * 100, goal)
  end

  defp quest_progression_label(player) do
    case quest_progress(player) do
      {count, 1} -> "#{count}/1 Training runs"
      {count, goal} -> "#{count}/#{goal} Avatars"
    end
  end

  defp quest_progress(%{pve_tier: tier, pve_progression: progression}) do
    quest = Game.get_quest(tier + 1)
    codes = Map.get(progression || %{}, quest.field, [])
    {min(length(codes), quest.goal), quest.goal}
  end

  defp quest_avatars_title(%{pve_tier: tier}) when tier < 2, do: nil
  defp quest_avatars_title(%{pve_progression: nil}), do: "Already trained: none"

  defp quest_avatars_title(%{pve_tier: tier, pve_progression: progression}) do
    quest = Game.get_quest(tier + 1)
    codes = Map.get(progression, quest.field, [])
    names = Enum.map(codes, &Moba.load_resource(&1).name)
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

  defp collection_avatar_class(%{"total_farm" => farm}) when farm == @max_total_farm, do: "avatar max-farm"
  defp collection_avatar_class(_), do: "avatar"

  defp training_difficulty_for(tier) do
    Map.get(Game.get_quest(tier), :difficulty) || Game.get_quest(7).difficulty
  end

  defp training_bonus_for(tier), do: Map.get(Game.get_quest(tier), :training_bonus)

  defp max_league_allowed_for(tier) do
    Map.get(Game.get_quest(tier), :max_league) || Game.get_quest(7).max_league
  end

  defp quest_shard_prize(tier), do: Game.get_quest(tier).prize
end
