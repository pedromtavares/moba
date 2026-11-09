defmodule MobaWeb.V2.DashboardLive do
  use MobaWeb, :v2_live_view

  import MobaWeb.V2.Components.ProgressionComponents
  import MobaWeb.CoreComponents, only: [icon: 1]

  embed_templates "dashboard_live/*"

  @runs_per_page 3

  def mount(_params, _session, socket) do
    %{assigns: %{current_player: player}} = socket

    socket = socket |> assign(:current_scope, Game.TeamRuns.scope(player)) |> socket_init(player)

    {:ok, socket}
  end

  def handle_event("toggle-runs", _, socket) do
    filter = if socket.assigns.filter == "unfinished", do: "finished", else: "unfinished"
    {:noreply, assign(socket, training_page(socket, filter, 0))}
  end

  def handle_event("page-runs", %{"direction" => direction}, socket) do
    %{run_page: page, more_runs: more_runs} = socket.assigns

    case direction do
      "previous" when page > 0 -> {:noreply, refresh_training_page(socket, page - 1)}
      "next" when more_runs -> {:noreply, refresh_training_page(socket, page + 1)}
      _ -> {:noreply, socket}
    end
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

      current_hero = if current_hero && hero.id == current_hero.id, do: nil, else: current_hero

      {:noreply, socket |> assign(current_hero: current_hero) |> refresh_training_page(socket.assigns.run_page)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("archive-team", %{"id" => id}, socket) do
    case Game.TeamRuns.archive(socket.assigns.current_scope, id) do
      {:ok, _team} ->
        has_active_team =
          not is_nil(Game.TeamRuns.active(socket.assigns.current_scope, socket.assigns.current_player.id))

        {:noreply, socket |> assign(has_active_team: has_active_team) |> refresh_training_page(socket.assigns.run_page)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Private functions

  defp socket_init(socket, player) do
    pending = training_page(socket, "unfinished", 0)
    initial_page = if empty_training_page?(pending), do: training_page(socket, "finished", 0), else: pending
    collection_codes = Enum.map(player.hero_collection || [], & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.reject(&(&1.code in collection_codes))

    register_to_train =
      is_nil(player.user_id) &&
        not empty_training_page?(
          if initial_page.filter == "finished", do: initial_page, else: training_page(socket, "finished", 0)
        )

    socket
    |> assign(initial_page)
    |> assign(
      sidebar_code: "base",
      register_to_train: register_to_train,
      guide_training_cta:
        register_to_train ||
          (player.user_id != nil && Phoenix.Flash.get(socket.assigns.flash, :training_registered) != nil),
      has_active_team: pending.visible_teams != [],
      blank_collection: blank_collection
    )
  end

  defp training_cta_path(%{register_to_train: true}), do: ~p"/users/register?from=training"
  defp training_cta_path(_assigns), do: ~p"/new"

  defp training_cta_label(true), do: "Register to continue training"
  defp training_cta_label(false), do: "Start training"

  defp refresh_training_page(socket, page) do
    result = training_page(socket, socket.assigns.filter, page)

    if page > 0 and empty_training_page?(result) do
      refresh_training_page(socket, page - 1)
    else
      assign(socket, result)
    end
  end

  defp empty_training_page?(page), do: page.visible_teams == [] and page.visible_heroes == []

  defp training_page(socket, filter, page) do
    scope = socket.assigns.current_scope
    offset = page * @runs_per_page

    # Teams are listed before solo heroes. Fetch one extra run to enable the next arrow.
    teams = training_teams(scope, filter, offset + @runs_per_page + 1, 0)
    visible_teams = Enum.slice(teams, offset, @runs_per_page)
    hero_offset = max(offset - length(teams), 0)

    heroes =
      if length(teams) <= offset + @runs_per_page do
        Game.Heroes.list_solo_training(scope, filter, @runs_per_page + 1 - length(visible_teams), hero_offset)
      else
        []
      end

    %{
      filter: filter,
      run_page: page,
      visible_teams: visible_teams,
      visible_heroes: Enum.take(heroes, @runs_per_page - length(visible_teams)),
      more_runs: length(teams) > offset + @runs_per_page or length(visible_teams) + length(heroes) > @runs_per_page
    }
  end

  defp training_teams(scope, filter, limit, offset) do
    records = Game.TeamRuns.list_training(scope, scope.player_id, filter, limit, offset)

    cards =
      Enum.flat_map(records, fn record ->
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

    if length(records) == limit and length(cards) < limit do
      cards ++ training_teams(scope, filter, limit - length(cards), offset + limit)
    else
      cards
    end
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

  @max_total_farm Moba.max_total_farm()

  defp undefeated_avatar?(%{"total_farm" => farm}), do: farm == @max_total_farm
  defp undefeated_avatar?(_), do: false

  defp training_difficulty_for(tier) do
    Map.get(Game.get_quest(tier), :difficulty) || Game.get_quest(7).difficulty
  end

  defp training_bonus_for(tier), do: Map.get(Game.get_quest(tier), :training_bonus)

  defp max_league_allowed_for(tier) do
    Map.get(Game.get_quest(tier), :max_league) || Game.get_quest(7).max_league
  end

  defp quest_shard_prize(tier), do: Game.get_quest(tier).prize
end
