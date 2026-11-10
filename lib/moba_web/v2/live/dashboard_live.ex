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

  def handle_params(%{"avatar" => code}, _uri, socket) do
    socket = socket |> browse_avatar(code) |> assign(avatar_deep_link: true, avatar_panel: "skins")
    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket = if socket.assigns.avatar_deep_link, do: close_avatar(socket), else: socket
    {:noreply, assign(socket, :avatar_deep_link, false)}
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

  def handle_event("browse-avatar", %{"code" => code}, socket) do
    {:noreply, browse_avatar(socket, code)}
  end

  def handle_event("close-avatar", _, %{assigns: %{avatar_deep_link: true}} = socket) do
    {:noreply, push_patch(socket, to: ~p"/base")}
  end

  def handle_event("close-avatar", _, socket) do
    {:noreply, close_avatar(socket)}
  end

  def handle_event("avatar-panel", %{"panel" => panel}, socket) when panel in ["runs", "skins"] do
    {:noreply, assign(socket, avatar_panel: panel)}
  end

  def handle_event("page-avatar-runs", %{"direction" => direction}, %{assigns: %{avatar_runs: runs}} = socket)
      when not is_nil(runs) do
    case direction do
      "previous" when runs.run_page > 0 -> {:noreply, load_avatar_runs(socket, runs.run_page - 1)}
      "next" when runs.more_runs -> {:noreply, load_avatar_runs(socket, runs.run_page + 1)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("page-avatar-runs", _, socket), do: {:noreply, socket}

  def handle_event("preview-skin", %{"code" => code}, socket) do
    case Enum.find(socket.assigns.avatar_skins, &(&1.code == code)) do
      nil -> {:noreply, socket}
      skin -> {:noreply, assign(socket, selected_skin: skin)}
    end
  end

  def handle_event("unlock-avatar", _, %{assigns: %{selected_avatar: avatar}} = socket) do
    player = socket.assigns.current_player

    if player.user && avatar && avatar.code != "tinker" && !avatar_unlocked?(avatar, socket.assigns.unlocked_codes) do
      socket = buy_unlock(socket, avatar)
      {:noreply, open_avatar(socket, avatar)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("unlock-skin", _, %{assigns: %{selected_skin: skin, selected_avatar: avatar}} = socket) do
    player = socket.assigns.current_player

    if player.user && avatar && skin && skin.id && skin.avatar_code == avatar.code &&
         avatar_unlocked?(avatar, socket.assigns.unlocked_codes) &&
         skin_league_met?(skin, Game.get_player!(player.id)) do
      {:noreply, buy_unlock(socket, skin)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("equip-skin", _, socket) do
    %{current_player: player, selected_avatar: avatar, selected_skin: skin, skin_hero: target} = socket.assigns

    with %{id: user_id} <- player.user,
         %{code: code} <- avatar,
         %{avatar_code: ^code} <- skin,
         true <- is_nil(skin.id) || skin.code in Accounts.unlocked_codes_for(Accounts.get_user_with_unlocks!(user_id)),
         %{id: id} <- target,
         hero when not is_nil(hero) <- Game.Heroes.get_finished_avatar_hero(socket.assigns.current_scope, id, code) do
      Game.set_skin!(hero, skin)
      Game.broadcast_to_hero(id)
      {:noreply, load_avatar_runs(socket, socket.assigns.avatar_runs.run_page)}
    else
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

      socket = assign(socket, current_hero: current_hero)

      socket =
        if hero.finished_at do
          collection = Game.get_player!(player.id).hero_collection
          socket |> assign(current_player: %{player | hero_collection: collection}) |> assign_blank_collection()
        else
          socket
        end

      {:noreply, refresh_visible_runs(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("archive-team", %{"id" => id}, socket) do
    case Game.TeamRuns.archive(socket.assigns.current_scope, id) do
      {:ok, _team} ->
        has_active_team =
          not is_nil(Game.TeamRuns.active(socket.assigns.current_scope, socket.assigns.current_player.id))

        {:noreply, socket |> assign(has_active_team: has_active_team) |> refresh_visible_runs()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Private functions

  defp socket_init(socket, player) do
    pending = training_page(socket, "unfinished", 0)
    initial_page = if empty_training_page?(pending), do: training_page(socket, "finished", 0), else: pending
    avatars = Game.list_avatars()

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
      avatar_catalog: avatars,
      unlocked_codes: if(player.user, do: Accounts.unlocked_codes_for(player.user), else: []),
      selected_avatar: nil,
      avatar_deep_link: false,
      avatar_runs: nil,
      avatar_skins: [],
      selected_skin: nil,
      skin_hero: nil,
      avatar_panel: "runs"
    )
    |> assign_blank_collection()
  end

  defp assign_blank_collection(%{assigns: %{current_player: player, avatar_catalog: avatars}} = socket) do
    codes = Enum.map(player.hero_collection || [], & &1["code"])
    assign(socket, blank_collection: Enum.reject(avatars, &(&1.code in codes)))
  end

  defp browse_avatar(socket, code) do
    case Enum.find(socket.assigns.avatar_catalog, &(&1.code == code)) do
      nil -> socket
      avatar -> open_avatar(socket, avatar)
    end
  end

  defp close_avatar(socket) do
    socket |> assign(selected_avatar: nil, avatar_runs: nil) |> refresh_training_page(socket.assigns.run_page)
  end

  defp open_avatar(socket, avatar) do
    socket =
      assign(socket,
        selected_avatar: avatar,
        avatar_panel: "runs",
        selected_skin: nil,
        avatar_skins: [],
        skin_hero: nil,
        avatar_runs: nil
      )

    if avatar_unlocked?(avatar, socket.assigns.unlocked_codes) do
      skins = [%{Game.default_skin(avatar.code) | name: "Default Skin"} | Game.list_avatar_skins(avatar.code)]
      socket |> assign(avatar_skins: skins) |> load_avatar_runs(0)
    else
      assign(socket, :selected_avatar, Game.get_avatar!(avatar.id))
    end
  end

  defp load_avatar_runs(socket, page) do
    code = socket.assigns.selected_avatar.code
    runs = training_page(socket, "finished", page, code)

    if page > 0 and empty_training_page?(runs) do
      load_avatar_runs(socket, page - 1)
    else
      hero =
        case runs.visible_teams do
          [team] ->
            team.hero_ids
            |> Game.get_heroes()
            |> Enum.find(&(&1.avatar.code == code && is_nil(&1.archived_at)))

          [] ->
            List.first(runs.visible_heroes)
        end

      skins = socket.assigns.avatar_skins
      equipped = Enum.find(skins, &(&1.id == (hero && hero.skin_id)))

      assign(socket,
        avatar_runs: %{runs | visible_teams: [], visible_heroes: List.wrap(hero)},
        skin_hero: hero,
        selected_skin: equipped || hd(skins)
      )
    end
  end

  defp refresh_visible_runs(%{assigns: %{avatar_runs: runs, selected_avatar: avatar}} = socket)
       when not is_nil(avatar) and not is_nil(runs),
       do: load_avatar_runs(socket, runs.run_page)

  defp refresh_visible_runs(socket), do: refresh_training_page(socket, socket.assigns.run_page)

  defp buy_unlock(%{assigns: %{current_player: player}} = socket, resource) do
    user = Accounts.buy_unlock!(player.user, resource)
    assign(socket, current_player: %{player | user: user}, unlocked_codes: Accounts.unlocked_codes_for(user))
  end

  defp avatar_unlocked?(%{level_requirement: nil}, _), do: true
  defp avatar_unlocked?(avatar, codes), do: avatar.code in codes

  defp skin_league_met?(skin, player) do
    Enum.any?(player.hero_collection || [], &(&1["code"] == skin.avatar_code && &1["tier"] >= skin.league_tier))
  end

  defp skin_background(%{id: nil}, avatar), do: GH.background_url(avatar)
  defp skin_background(skin, _avatar), do: GH.background_url(skin)

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

  defp training_page(socket, filter, page, avatar_code \\ nil) do
    scope = socket.assigns.current_scope
    page_size = if avatar_code, do: 1, else: @runs_per_page
    offset = page * page_size

    # Teams are listed before solo heroes. Fetch one extra run to enable the next arrow.
    teams = training_teams(scope, filter, offset + page_size + 1, 0, avatar_code)
    visible_teams = Enum.slice(teams, offset, page_size)
    hero_offset = max(offset - length(teams), 0)

    heroes =
      if length(teams) <= offset + page_size do
        Game.Heroes.list_solo_training(scope, filter, page_size + 1 - length(visible_teams), hero_offset, avatar_code)
      else
        []
      end

    %{
      filter: filter,
      run_page: page,
      visible_teams: visible_teams,
      visible_heroes: Enum.take(heroes, page_size - length(visible_teams)),
      more_runs: length(teams) > offset + page_size or length(visible_teams) + length(heroes) > page_size
    }
  end

  defp training_teams(scope, filter, limit, offset, avatar_code) do
    records = Game.TeamRuns.list_training(scope, scope.player_id, filter, limit, offset, avatar_code)

    cards =
      Enum.flat_map(records, fn record ->
        with {:ok, run} <- Game.TeamRuns.read_state(record) do
          heroes = Game.TeamTraining.team(run) |> Enum.map(& &1.hero)

          [
            %{
              id: record.id,
              hero_ids: record.hero_ids,
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
      cards ++ training_teams(scope, filter, limit - length(cards), offset + limit, avatar_code)
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
