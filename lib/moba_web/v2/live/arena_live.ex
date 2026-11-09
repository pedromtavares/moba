defmodule MobaWeb.V2.ArenaLive do
  use MobaWeb, :v2_live_view
  on_mount MobaWeb.V2.Hooks.TeamAccess

  import MobaWeb.CoreComponents, only: [input: 1, icon: 1]
  import MobaWeb.V2.Components.HeroBarComponents

  alias MobaWeb.Presence

  embed_templates "arena_live/*"

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(sidebar_code: "arena")
      |> assign(team_form: to_form(%{"name" => ""}, as: :team))
      |> assign(hero: nil, editing: false, show_build: false, show_shop: false)

    if connected?(socket) do
      MobaWeb.subscribe("online")
      MobaWeb.subscribe("player-ranking")
    end

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> maybe_redirect_guest()
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def handle_event("standings-tab", %{"type" => mode}, socket) when mode in ["3v3", "1v1"] do
    {:noreply, assign(socket, ranking: ranking_for(mode), ranking_tab: mode)}
  end

  def handle_event("history-tab", %{"type" => tab}, socket) when tab in ["matches", "duels"] do
    {:noreply, assign(socket, history_tab: tab)}
  end

  def handle_event("toggle-auto-matchmaking", params, %{assigns: %{current_player: player}} = socket) do
    auto_matchmaking = not is_nil(Map.get(params, "value"))
    player = Game.update_preferences!(player, %{auto_matchmaking: auto_matchmaking})
    {:noreply, assign(socket, current_player: player)}
  end

  def handle_event("challenge", %{"id" => opponent_id}, %{assigns: %{current_player: player}} = socket) do
    opponent = Game.get_player!(opponent_id)

    if can_be_challenged?(player, Timex.now()) && can_be_challenged?(opponent, Timex.now()) do
      Game.duel_challenge(player, opponent)
      {:noreply, socket}
    else
      {:noreply, assign(socket, duel_opponents: opponents_from_presence(player), current_time: Timex.now())}
    end
  end

  def handle_event("matchmaking", _, %{assigns: %{current_player: player, pending_match: pending}} = socket) do
    match = if pending, do: pending, else: Game.manual_matchmaking!(player)

    if match do
      {:noreply, push_navigate(socket, to: preview_path(socket, ~p"/matches/#{match.id}"))}
    else
      {:noreply, socket |> assign(current_player: Game.get_player!(player.id)) |> assign_index()}
    end
  end

  def handle_event("season-duel", _, %{assigns: %{current_player: player, pending_duel: pending}} = socket) do
    opponent = if !pending, do: Game.duel_opponent(player)
    duel = pending || (opponent && Game.create_duel!(player, opponent, true))

    if duel do
      {:noreply, push_navigate(socket, to: preview_path(socket, ~p"/arena/#{duel.id}"))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set-status", _, %{assigns: %{pending_duel: pending}} = socket) when not is_nil(pending),
    do: {:noreply, socket}

  def handle_event("set-status", params, %{assigns: %{current_player: player}} = socket) do
    {player, duel_opponents} =
      if is_nil(Map.get(params, "value")) do
        {Game.set_player_unavailable!(player), []}
      else
        player = Game.set_player_available!(player)
        {player, opponents_from_presence(player)}
      end

    {:noreply, assign(socket, current_player: player, duel_opponents: duel_opponents, current_time: Timex.now())}
  end

  def handle_event("hero-list", _, socket) do
    %{trained_heroes: heroes, sort: sort} = socket.assigns
    {:noreply, assign(socket, heroes: sort_team_heroes(heroes, sort), heroes_tab: "trained")}
  end

  def handle_event("toggle-defensive", params, %{assigns: %{selected_team: team}} = socket) when not is_nil(team) do
    defensive = not is_nil(Map.get(params, "value"))
    team = Game.update_team!(team, %{defensive: defensive})
    {:noreply, socket |> assign(selected_team: team) |> update_teams()}
  end

  def handle_event("new-team", %{"team" => %{"name" => name}}, socket) do
    team = Game.create_team!(%{name: name, player_id: socket.assigns.current_player.id})

    {:noreply,
     socket
     |> assign(
       teams: socket.assigns.teams ++ [team],
       selected_team: team,
       teams_page: div(length(socket.assigns.teams), if(socket.assigns.hero, do: 3, else: 5))
     )
     |> reset_team_form()}
  end

  def handle_event("select-team", %{"id" => id}, socket) do
    team = Enum.find(socket.assigns.teams, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, selected_team: team)}
  end

  def handle_event("remove-team", _, %{assigns: %{selected_team: nil}} = socket), do: {:noreply, socket}

  def handle_event("remove-team", _, %{assigns: %{selected_team: selected_team, teams: teams}} = socket) do
    Game.delete_team!(selected_team)
    teams = teams -- [selected_team]
    {:noreply, assign(socket, selected_team: List.first(teams), teams: teams, teams_page: 0)}
  end

  def handle_event("edit-hero", %{"id" => id}, %{assigns: %{current_player: current_player}} = socket) do
    hero = Game.get_hero!(id)

    if hero.player_id == current_player.id do
      {:noreply,
       assign(socket, hero: hero, editing: false, show_build: false, show_shop: false, heroes_page: 0, teams_page: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close-customization", _, socket) do
    {:noreply,
     assign(socket, hero: nil, editing: false, show_build: false, show_shop: false, heroes_page: 0, teams_page: 0)}
  end

  def handle_event("source-page", %{"source" => source, "direction" => direction}, socket)
      when source in ["teams", "heroes"] and direction in ["previous", "next"] do
    {items, page_key, page_size} =
      if source == "teams" do
        {socket.assigns.teams, :teams_page, if(socket.assigns.hero, do: 3, else: 5)}
      else
        {socket.assigns.heroes, :heroes_page, heroes_per_page(socket.assigns.hero)}
      end

    step = if direction == "next", do: 1, else: -1
    page = (socket.assigns[page_key] + step) |> max(0) |> min(div(max(length(items) - 1, 0), page_size))
    {:noreply, assign(socket, page_key, page)}
  end

  def handle_event(
        "add-hero",
        %{"id" => id} = params,
        %{assigns: %{selected_team: %{id: team_id} = selected_team, current_player: player}} = socket
      ) do
    with ^team_id <- Map.get(params, "lineup_id", team_id),
         {:ok, hero_id} <- Ecto.Type.cast(:integer, id),
         {:ok, team} <- Game.Teams.add_pick(player, selected_team, hero_id) do
      {:noreply, socket |> assign(selected_team: team) |> update_teams()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("add-hero", _, socket), do: {:noreply, socket}

  def handle_event("remove-hero", %{"id" => _id}, %{assigns: %{selected_team: nil}} = socket), do: {:noreply, socket}

  def handle_event("remove-hero", %{"id" => id}, %{assigns: %{selected_team: selected_team}} = socket) do
    pick_ids = sanitize_pick_ids(selected_team.pick_ids -- [String.to_integer(id)])
    team = Game.update_team!(selected_team, %{pick_ids: pick_ids})
    {:noreply, socket |> assign(selected_team: team) |> update_teams()}
  end

  def handle_event(
        "reorder-lineup",
        %{"lineup_id" => id, "hero_ids" => ids},
        %{assigns: %{live_action: :edit}} = socket
      )
      when is_list(ids) and length(ids) <= 3 do
    %{selected_team: selected, current_player: player} = socket.assigns

    with %{id: ^id} <- selected,
         {:ok, team} <- Game.Teams.reorder_lineup(player, selected, ids) do
      {:noreply, socket |> assign(selected_team: team) |> update_teams()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("reorder-lineup", _, socket), do: {:noreply, socket}

  def handle_event("sort", _, %{assigns: %{sort: sort, trained_heroes: trained_heroes}} = socket) do
    sort =
      case sort do
        :farm -> :recent
        :recent -> :rank
        :rank -> :farm
      end

    {:noreply,
     assign(socket,
       sort: sort,
       heroes: sort_team_heroes(trained_heroes, sort),
       heroes_tab: "trained",
       heroes_page: 0
     )}
  end

  def handle_event("start-edit", _, %{assigns: %{hero: hero}} = socket) when not is_nil(hero) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("start-edit", _, socket), do: {:noreply, socket}

  def handle_event("cancel-edit", _, socket) do
    {:noreply, assign(socket, editing: false)}
  end

  def handle_event("finalize-edit", params, %{assigns: %{hero: current, current_player: player}} = socket)
      when not is_nil(current) do
    hero =
      Game.update_hero!(current, %{
        skill_order: params_to_order(params["skill_order"]),
        item_order: params_to_order(params["item_order"])
      })

    {:noreply, refresh_edit_hero(socket, player, hero)}
  end

  def handle_event("finalize-edit", _, socket), do: {:noreply, socket}

  def handle_event("show-build", _, %{assigns: %{hero: hero}} = socket) when not is_nil(hero) do
    {:noreply, assign(socket, show_build: true)}
  end

  def handle_event("show-build", _, socket), do: {:noreply, socket}

  def handle_event("show-navigation", _, socket) do
    {:noreply, assign(socket, show_build: false)}
  end

  def handle_event("toggle-shop", _, %{assigns: %{hero: hero}} = socket) when not is_nil(hero) do
    {:noreply, assign(socket, show_shop: !socket.assigns.show_shop)}
  end

  def handle_event("toggle-shop", _, socket), do: {:noreply, socket}

  def handle_event("close-shop", _, socket) do
    {:noreply, assign(socket, show_shop: false)}
  end

  def handle_event("open-shop-item", %{"code" => code}, socket) do
    {:noreply, open_shop_item(socket, socket.assigns.hero, code)}
  end

  def handle_event("level", _, %{assigns: %{hero: current, current_player: player}} = socket)
      when not is_nil(current) do
    hero =
      if Application.get_env(:moba, :env) == :dev do
        Game.level_cheat(current)
      else
        current
      end

    Game.broadcast_to_hero(current.id)
    {:noreply, refresh_edit_hero(socket, player, hero)}
  end

  def handle_event("level", _, socket), do: {:noreply, socket}

  def handle_event("skill", %{"code" => code}, %{assigns: %{hero: current, current_player: player}} = socket)
      when not is_nil(current) do
    hero = Game.level_up_skill!(current, code)
    Game.broadcast_to_hero(hero.id)
    {:noreply, refresh_edit_hero(socket, player, hero)}
  end

  def handle_event("skill", _, socket), do: {:noreply, socket}

  def handle_event("buy", %{"code" => code}, %{assigns: %{hero: hero, current_player: player}} = socket)
      when not is_nil(hero) do
    updated_hero = Game.buy_item!(hero, cached_item!(code))
    Game.broadcast_to_hero(updated_hero.id)
    {:noreply, refresh_edit_hero(socket, player, updated_hero)}
  end

  def handle_event("buy", _, socket), do: {:noreply, socket}

  def handle_event("sell", %{"code" => code}, %{assigns: %{hero: hero, current_player: player}} = socket)
      when not is_nil(hero) do
    updated_hero = Game.sell_item!(hero, hero_item_by_code!(hero, code))
    Game.broadcast_to_hero(updated_hero.id)
    {:noreply, refresh_edit_hero(socket, player, updated_hero)}
  end

  def handle_event("sell", _, socket), do: {:noreply, socket}

  def handle_event(
        "finish-transmute",
        %{"transmute_code" => transmute_code, "recipe_codes" => recipe_codes},
        %{assigns: %{hero: hero, current_player: player}} = socket
      )
      when not is_nil(hero) do
    transmute = cached_item!(transmute_code)
    recipe = hero_items_by_codes(hero, recipe_codes)
    updated_hero = Game.transmute_item!(hero, recipe, transmute)
    Game.broadcast_to_hero(updated_hero.id)
    {:noreply, refresh_edit_hero(socket, player, updated_hero)}
  end

  def handle_event("finish-transmute", _, socket), do: {:noreply, socket}

  def handle_info(%{event: "presence_diff"}, socket), do: {:noreply, refresh_live_opponents(socket)}

  def handle_info({"availability", _}, %{assigns: %{live_action: :index, current_player: %{id: id}}} = socket) do
    player = Game.get_player!(id)

    {:noreply,
     socket
     |> assign(current_player: player, pending_duel: Game.Duels.pending_duel(player))
     |> refresh_live_opponents()}
  end

  def handle_info({"availability", _}, socket), do: {:noreply, socket}

  def handle_info({"ranking", _}, %{assigns: %{current_player: %{id: id}}} = socket) do
    player = Game.get_player!(id)
    {:noreply, socket |> assign(current_player: player) |> assign_index()}
  end

  def render(%{live_action: :edit} = assigns), do: edit(assigns)
  def render(assigns), do: index(assigns)

  defp apply_action(socket, :edit, params), do: assign_edit(socket, params)
  defp apply_action(socket, _, _params), do: assign_index(socket)

  defp assign_index(%{assigns: %{current_player: player}} = socket) do
    current_time = Timex.now()
    duels = Game.list_duels(player)
    duel_opponents = opponents_from_presence(player)
    pending_duel = Game.Duels.pending_duel(player)
    ranking_tab = Map.get(socket.assigns, :ranking_tab, "3v3")
    ranking = ranking_for(ranking_tab)

    socket
    |> assign_new(:history_tab, fn -> "matches" end)
    |> assign(
      current_time: current_time,
      duels: duels,
      finished_duels: Enum.filter(duels, &(&1.phase == "finished")),
      reward_games: Game.Arena.daily_reward_games(player),
      recent_results: Game.Matches.recent_results(player),
      duel_opponents: duel_opponents,
      pending_duel: pending_duel,
      ranking: ranking,
      ranking_tab: ranking_tab
    )
    |> list_matches()
  end

  defp heroes_per_page(nil), do: 24
  defp heroes_per_page(_hero), do: 16

  defp assign_edit(%{assigns: %{current_player: player}} = socket, params) do
    teams = Game.list_teams(player)
    heroes_tab = "trained"
    trained_heroes = Game.trained_pvp_heroes(player.id, [], 200, :farm)

    return_match_id =
      case Integer.parse(params["match_id"] || "") do
        {id, ""} when id > 0 ->
          Game.Matches.match_id_for_player(player, id) || Game.Matches.match_id_for_player(player)

        _ ->
          Game.Matches.match_id_for_player(player)
      end

    assign(socket,
      hero: nil,
      heroes_tab: heroes_tab,
      heroes: trained_heroes,
      trained_heroes: trained_heroes,
      teams: teams,
      teams_page: 0,
      heroes_page: 0,
      sort: :farm,
      selected_team: List.first(teams),
      return_match_id: return_match_id,
      team_form: socket.assigns.team_form
    )
  end

  defp list_matches(%{assigns: %{current_player: player}} = socket) do
    all_matches = Game.list_matches(player)
    matches = Enum.filter(all_matches, &(&1.phase == "scored"))
    pending_match = Game.Matches.pending_match(player)
    manual_matches = Enum.filter(all_matches, &(&1.type == "manual"))
    auto_matches = Enum.filter(all_matches, &(&1.type == "auto"))

    assign(socket,
      auto_matches: auto_matches,
      manual_matches: manual_matches,
      matches: matches,
      pending_match: pending_match
    )
  end

  defp maybe_redirect_guest(%{assigns: %{current_player: %{user_id: nil}}} = socket) do
    redirect(socket, to: preview_path(socket, ~p"/users/register"))
  end

  defp maybe_redirect_guest(socket), do: socket

  defp refresh_live_opponents(%{assigns: %{live_action: :index, current_player: player}} = socket) do
    assign(socket,
      duel_opponents: opponents_from_presence(player),
      current_time: Timex.now()
    )
  end

  defp refresh_live_opponents(socket), do: socket

  defp opponents_from_presence(%{status: "available"} = player) do
    online_ids =
      Presence.list("online")
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)
      |> Enum.map(& &1.player_id)

    player
    |> Game.duel_opponents(online_ids)
    |> Enum.sort_by(& &1.user.last_online_at, {:asc, Date})
  end

  defp opponents_from_presence(_), do: []

  defp ranking_for("3v3"), do: Moba.daily_ranking()
  defp ranking_for("1v1"), do: Game.season_points_ranking(Moba.daily_ranking_limit())

  defp arena_bracket(%{pvp_tier: 2}), do: "Immortals"
  defp arena_bracket(%{pvp_tier: 1}), do: "Shadows"
  defp arena_bracket(_), do: "Plebs"

  defp arena_movement(%{pvp_tier: 1, ranking: rank}, _) when rank in 6..9, do: {:up, "Immortals"}
  defp arena_movement(%{pvp_tier: 0, ranking: rank}, _) when rank in 26..31, do: {:up, "Shadows"}
  defp arena_movement(%{pvp_tier: 1, ranking: rank}, _) when rank in 20..25, do: {:down, "Plebs"}

  defp arena_movement(%{pvp_tier: 2, id: id, ranking: rank}, ranking) when is_integer(rank) do
    leader =
      ranking
      |> Enum.filter(&(&1.pvp_tier == 2))
      |> Enum.max_by(&{&1.daily_wins, &1.pvp_points}, fn -> nil end)

    cond do
      is_nil(leader) -> nil
      leader.id != id -> {:down, "Shadows"}
      rank != 1 -> {:up, "The Immortal"}
      true -> nil
    end
  end

  defp arena_movement(_, _), do: nil

  defp update_teams(%{assigns: %{teams: teams, selected_team: %{id: selected_id} = selected}} = socket) do
    teams =
      Enum.map(teams, fn
        %{id: ^selected_id} -> selected
        team -> team
      end)

    assign(socket, teams: teams)
  end

  defp update_teams(socket), do: socket

  defp refresh_edit_hero(socket, player, hero) do
    teams = Game.list_teams(player)
    trained_heroes = Game.trained_pvp_heroes(player.id, [], 200, :farm)
    selected_team_id = socket.assigns.selected_team && socket.assigns.selected_team.id
    selected_team = Enum.find(teams, &(&1.id == selected_team_id)) || List.first(teams)

    assign(socket,
      hero: hero,
      editing: false,
      show_shop: socket.assigns.show_shop,
      teams: teams,
      selected_team: selected_team,
      trained_heroes: trained_heroes,
      heroes: sort_team_heroes(trained_heroes, socket.assigns.sort)
    )
  end

  defp sort_team_heroes(heroes, :farm), do: heroes
  defp sort_team_heroes(heroes, :recent), do: Enum.sort_by(heroes, & &1.finished_at, {:desc, DateTime})
  defp sort_team_heroes(heroes, :rank), do: Enum.sort_by(heroes, & &1.pve_ranking)

  defp sanitize_pick_ids(pick_ids), do: pick_ids |> Enum.uniq() |> Enum.take(3)

  defp reset_team_form(socket), do: assign(socket, team_form: to_form(%{"name" => ""}, as: :team))

  defp can_be_challenged?(%{last_challenge_at: nil}, _current_time), do: true

  defp can_be_challenged?(%{last_challenge_at: time}, current_time) do
    Timex.diff(Timex.shift(time, seconds: 30), current_time) < 0
  end

  defp match_progress_percentage(matches, other_matches) do
    count = length(matches)
    count * 100 / max(Moba.daily_match_limit(), count + length(other_matches))
  end

  defp manual_match_limit_reached?(player, manual_matches) do
    player.daily_matches > Moba.daily_match_limit() || length(manual_matches) >= Moba.daily_match_limit()
  end

  defp params_to_order(nil), do: []

  defp params_to_order(params) do
    Enum.sort(params, fn {_, v1}, {_, v2} ->
      String.to_integer(v1) <= String.to_integer(v2)
    end)
    |> Enum.map(fn {code, _} -> code end)
  end

  defp cached_item!(code) do
    Enum.find(Moba.cached_items(), &(&1.code == code))
  end

  defp hero_item_by_code!(hero, code) do
    Enum.find(hero.items, &(&1.code == code))
  end

  defp hero_items_by_codes(hero, codes) do
    {items, _remaining} =
      Enum.map_reduce(codes, hero.items, fn code, remaining_items ->
        {item, updated_items} = pop_item_by_code(remaining_items, code)
        {item, updated_items}
      end)

    items
  end

  defp pop_item_by_code(items, code) do
    {matched, rest} = Enum.split_with(items, &(&1.code == code))
    {List.first(matched), Enum.drop(matched, 1) ++ rest}
  end

  defp tier_title(%{pvp_tier: 2, ranking: 1}), do: "You are The Immortal, defend your title."
  defp tier_title(%{pvp_tier: 2}), do: "You are an Immortal, fighting among the best for the title."
  defp tier_title(%{pvp_tier: 1}), do: "You are a Shadow, rise above the rest to become an Immortal."
  defp tier_title(_), do: "You are a Pleb, fight to become a Shadow."

  defp reset_timer do
    Moba.current_season().last_pvp_update_at
    |> Timex.shift(days: 1)
    |> Timex.format("{relative}", :relative)
    |> elem(1)
    |> then(&"A new fight begins #{&1}")
  end

  defp daily_reset_label do
    reset_at = Moba.current_season().last_pvp_update_at |> Timex.shift(days: 1) |> Timex.to_datetime()

    if DateTime.compare(reset_at, DateTime.utc_now()) == :gt do
      "Resets #{Timex.format!(reset_at, "{relative}", :relative)}"
    else
      "Daily reset pending"
    end
  end

  defp tier_buff_pct(player), do: GH.immortal_streak_debuff_percent(player)

  defp match_result_label(%{phase: phase}) when phase != "scored", do: "In Progress"
  defp match_result_label(%{winner_id: winner_id, player_id: player_id}) when winner_id == player_id, do: "Victory"
  defp match_result_label(_), do: "Defeat"

  defp match_result_class(%{phase: phase}) when phase != "scored", do: ""
  defp match_result_class(%{winner_id: winner_id, player_id: player_id}) when winner_id == player_id, do: "text-success"
  defp match_result_class(_), do: "text-muted"

  defp duel_result_label(duel, player_id) do
    cond do
      duel.phase != "finished" -> "In Progress"
      is_nil(duel.winner_player) -> "Tie"
      duel.winner_player_id == player_id -> "Victory"
      true -> "Defeat"
    end
  end

  defp duel_result_class(duel, player_id) do
    cond do
      duel.phase != "finished" -> ""
      is_nil(duel.winner_player) -> "text-white"
      duel.winner_player_id == player_id -> "text-success"
      true -> "text-muted"
    end
  end

  defp rewards_badge(0), do: nil

  defp rewards_badge(points) when points > 0,
    do: %{class: "badge badge-pill badge-light-success", label: "+#{points} Arena Rating"}

  defp rewards_badge(points), do: %{class: "badge badge-pill badge-light-dark", label: "#{points} Arena Rating"}

  defp duel_badge_class(%{type: "pvp"}), do: "badge badge-light-danger"
  defp duel_badge_class(%{type: "elite_matchmaking"}), do: "badge badge-light-warning"
  defp duel_badge_class(_), do: "badge badge-light-primary"

  defp match_type_title(%{type: "auto"}), do: "Auto match"
  defp match_type_title(_), do: "Manual match"

  defp opponent_for(duel, %{id: id}) when duel.player_id == id, do: duel.opponent_player
  defp opponent_for(duel, _player), do: duel.player

  defp ranking_inclusion?(ranking, player), do: Enum.any?(ranking, &(&1.id == player.id))
end
