defmodule MobaWeb.V2.ArenaLive do
  use MobaWeb, :v2_live_view

  alias MobaWeb.Presence
  alias MobaWeb.V2.TutorialComponent

  embed_templates "arena_live/*"

  def mount(_params, _session, %{assigns: %{current_player: player}} = socket) do
    socket =
      socket
      |> assign(sidebar_code: "arena", tutorial_step: player.tutorial_step)
      |> assign(team_form: to_form(%{"name" => ""}, as: :team))
      |> assign(hero: nil, editing: false, show_build: false)

    if connected?(socket) do
      TutorialComponent.subscribe(player.id)
      MobaWeb.subscribe("online")
      MobaWeb.subscribe("player-ranking")
    end

    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> maybe_redirect_guest()
      |> apply_action(socket.assigns.live_action)

    {:noreply, socket}
  end

  def handle_event("tiered-ranking", %{"type" => ranking_tab}, socket) do
    ranking = tiered_ranking(%{pvp_tier: pvp_tier_for(ranking_tab)})
    {:noreply, assign(socket, ranking: ranking, ranking_tab: ranking_tab)}
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
      {:noreply, push_navigate(socket, to: ~p"/matches/#{match.id}")}
    else
      {:noreply, socket |> assign(current_player: Game.get_player!(player.id)) |> assign_index()}
    end
  end

  def handle_event("season-duel", _, %{assigns: %{current_player: player}} = socket) do
    opponent = Game.duel_opponent(player)
    duel = opponent && Game.create_duel!(player, opponent, true)

    if duel do
      {:noreply, push_navigate(socket, to: ~p"/arena/#{duel.id}")}
    else
      {:noreply, socket}
    end
  end

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

  def handle_event("finish-tutorial", _, socket) do
    socket = TutorialComponent.next_step(socket, 31)
    handle_event("matchmaking", %{}, socket)
  end

  def handle_event("hero-list", %{"type" => heroes_tab}, socket) do
    {:noreply, assign(socket, heroes: heroes_for(socket, heroes_tab), heroes_tab: heroes_tab)}
  end

  def handle_event("toggle-defensive", params, %{assigns: %{selected_team: team}} = socket) when not is_nil(team) do
    defensive = not is_nil(Map.get(params, "value"))
    team = Game.update_team!(team, %{defensive: defensive})
    {:noreply, socket |> assign(selected_team: team) |> update_teams()}
  end

  def handle_event("new-team", %{"team" => %{"name" => name}}, socket) do
    team = Game.create_team!(%{name: name, player_id: socket.assigns.current_player.id})
    {:noreply, socket |> assign(teams: socket.assigns.teams ++ [team], selected_team: team) |> reset_team_form()}
  end

  def handle_event("select-team", %{"id" => id}, socket) do
    team = Enum.find(socket.assigns.teams, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, selected_team: team)}
  end

  def handle_event("remove-team", _, %{assigns: %{selected_team: nil}} = socket), do: {:noreply, socket}

  def handle_event("remove-team", _, %{assigns: %{selected_team: selected_team, teams: teams}} = socket) do
    Game.delete_team!(selected_team)
    teams = teams -- [selected_team]
    {:noreply, assign(socket, selected_team: List.first(teams), teams: teams)}
  end

  def handle_event("edit-hero", %{"id" => id}, %{assigns: %{current_player: current_player}} = socket) do
    hero = Game.get_hero!(id)

    if hero.player_id == current_player.id do
      {:noreply, assign(socket, hero: hero, editing: false, show_build: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add-hero", %{"id" => _id}, %{assigns: %{selected_team: nil}} = socket), do: {:noreply, socket}

  def handle_event("add-hero", %{"id" => id}, socket) do
    hero = Game.get_hero!(id)

    if valid_addition?(hero, socket) do
      selected_team = socket.assigns.selected_team
      pick_ids = sanitize_pick_ids(selected_team.pick_ids ++ [hero.id])
      team = Game.update_team!(selected_team, %{pick_ids: pick_ids})
      {:noreply, socket |> assign(selected_team: team) |> update_teams()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove-hero", %{"id" => _id}, %{assigns: %{selected_team: nil}} = socket), do: {:noreply, socket}

  def handle_event("remove-hero", %{"id" => id}, %{assigns: %{selected_team: selected_team}} = socket) do
    pick_ids = sanitize_pick_ids(selected_team.pick_ids -- [String.to_integer(id)])
    team = Game.update_team!(selected_team, %{pick_ids: pick_ids})
    {:noreply, socket |> assign(selected_team: team) |> update_teams()}
  end

  def handle_event("move-up", %{"id" => id}, socket) do
    {:noreply, move(String.to_integer(id), -1, socket)}
  end

  def handle_event("move-down", %{"id" => id}, socket) do
    {:noreply, move(String.to_integer(id), 1, socket)}
  end

  def handle_event("sort", _, %{assigns: %{sort: sort, trained_heroes: trained_heroes}} = socket) do
    {sort, trained_heroes} =
      if sort == :recent do
        {:rank, Enum.sort_by(trained_heroes, & &1.pve_ranking)}
      else
        {:recent, Enum.sort_by(trained_heroes, & &1.finished_at, {:desc, Date})}
      end

    {:noreply,
     assign(socket, sort: sort, trained_heroes: trained_heroes, heroes: trained_heroes, heroes_tab: "trained")}
  end

  def handle_event("start-edit", _, %{assigns: %{hero: hero}} = socket) when not is_nil(hero) do
    {:noreply, assign(socket, editing: true, show_build: true)}
  end

  def handle_event("start-edit", _, socket), do: {:noreply, socket}

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

  def handle_info({:tutorial, %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def handle_info(
        %{event: "presence_diff"},
        %{assigns: %{current_player: player, last_presence_update: last_update}} = socket
      ) do
    ago = Timex.shift(Timex.now(), seconds: -10)

    if Timex.diff(ago, last_update) > 0 do
      {:noreply,
       assign(socket,
         duel_opponents: opponents_from_presence(player),
         last_presence_update: Timex.now(),
         current_time: Timex.now()
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({"ranking", _}, %{assigns: %{current_player: %{id: id}, ranking_tab: ranking_tab}} = socket) do
    player = Game.get_player!(id)
    ranking = tiered_ranking(%{pvp_tier: pvp_tier_for(ranking_tab)})
    {:noreply, socket |> assign(current_player: player, ranking: ranking) |> assign_index()}
  end

  def handle_info({:hero_bar_updated, hero}, %{assigns: %{current_player: player, hero: current_hero}} = socket)
      when not is_nil(current_hero) and current_hero.id == hero.id do
    {:noreply, refresh_edit_hero(socket, player, hero)}
  end

  def handle_info({:hero_bar_updated, _hero}, socket) do
    {:noreply, socket}
  end

  def render(%{live_action: :edit} = assigns), do: edit(assigns)
  def render(assigns), do: index(assigns)

  defp apply_action(socket, :edit), do: assign_edit(socket)
  defp apply_action(socket, _), do: assign_index(socket)

  defp assign_index(%{assigns: %{current_player: player}} = socket) do
    current_time = Timex.now()
    duels = Game.list_duels(player)
    duel_opponents = opponents_from_presence(player)
    pending_duel = Enum.find(duels, &(&1.phase != "finished"))
    ranking = tiered_ranking(player)
    ranking_tab = ranking_tab_for(player)

    socket
    |> assign(
      current_time: current_time,
      duels: duels,
      duel_opponents: duel_opponents,
      pending_duel: pending_duel,
      last_presence_update: Timex.now(),
      ranking: ranking,
      ranking_tab: ranking_tab
    )
    |> list_matches()
    |> TutorialComponent.next_step(30)
  end

  defp assign_edit(%{assigns: %{current_player: player}} = socket) do
    teams = Game.list_teams(player)
    heroes_tab = "trained"
    trained_heroes = Game.trained_pvp_heroes(player.id, [], 200) |> Enum.sort_by(& &1.pve_ranking)

    assign(socket,
      hero: nil,
      heroes_tab: heroes_tab,
      heroes: trained_heroes,
      trained_heroes: trained_heroes,
      teams: teams,
      sort: :rank,
      selected_team: List.first(teams),
      team_form: socket.assigns.team_form
    )
  end

  defp list_matches(%{assigns: %{current_player: player}} = socket) do
    all_matches = Game.list_matches(player)
    matches = Enum.filter(all_matches, &(&1.phase == "scored"))
    pending_match = Enum.find(all_matches, &(&1.phase != "scored"))
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
    redirect(socket, to: ~p"/users/register")
  end

  defp maybe_redirect_guest(socket), do: socket

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

  defp tiered_ranking(%{pvp_tier: tier}) do
    Moba.daily_ranking()
    |> Enum.filter(&(&1.pvp_tier == tier))
  end

  defp pvp_tier_for("immortals"), do: 2
  defp pvp_tier_for("shadows"), do: 1
  defp pvp_tier_for(_), do: 0

  defp ranking_tab_for(%{pvp_tier: 2}), do: "immortals"
  defp ranking_tab_for(%{pvp_tier: 1}), do: "shadows"
  defp ranking_tab_for(_), do: "plebs"

  defp heroes_for(%{assigns: %{trained_heroes: trained_heroes}}, "trained")
       when is_list(trained_heroes),
       do: trained_heroes

  defp heroes_for(%{assigns: %{current_player: player}}, "trained") do
    Game.trained_pvp_heroes(player.id, [], 200) |> Enum.sort_by(& &1.pve_ranking)
  end

  defp heroes_for(_, _), do: Moba.pve_ranking_available()

  defp move(_hero_id, _slide, %{assigns: %{selected_team: nil}} = socket), do: socket

  defp move(hero_id, slide, %{assigns: %{selected_team: selected_team}} = socket) do
    index = Enum.find_index(selected_team.pick_ids, &(&1 == hero_id))

    if is_nil(index) or index + slide < 0 or index + slide >= length(selected_team.pick_ids) do
      socket
    else
      pick_ids = Enum.slide(selected_team.pick_ids, index, index + slide)
      team = Game.update_team!(selected_team, %{pick_ids: pick_ids})
      socket |> assign(selected_team: team) |> update_teams()
    end
  end

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
    trained_heroes = Game.trained_pvp_heroes(player.id, [], 200) |> Enum.sort_by(& &1.pve_ranking)
    selected_team_id = socket.assigns.selected_team && socket.assigns.selected_team.id
    selected_team = Enum.find(teams, &(&1.id == selected_team_id)) || List.first(teams)
    heroes = if socket.assigns.heroes_tab == "trained", do: trained_heroes, else: Moba.pve_ranking_available()

    assign(socket,
      hero: hero,
      editing: false,
      teams: teams,
      selected_team: selected_team,
      trained_heroes: trained_heroes,
      heroes: heroes
    )
  end

  defp valid_addition?(hero, %{assigns: %{selected_team: selected_team, current_player: current_player}})
       when not is_nil(selected_team) do
    (hero.player_id == current_player.id || Game.available_hero?(hero)) &&
      length(selected_team.picks) < 5 &&
      not Enum.member?(selected_team.pick_ids, hero.id)
  end

  defp valid_addition?(_, _), do: false

  defp sanitize_pick_ids(pick_ids), do: Enum.uniq(pick_ids)

  defp reset_team_form(socket), do: assign(socket, team_form: to_form(%{"name" => ""}, as: :team))

  defp can_be_challenged?(%{last_challenge_at: nil}, _current_time), do: true

  defp can_be_challenged?(%{last_challenge_at: time}, current_time) do
    Timex.diff(Timex.shift(time, seconds: 30), current_time) < 0
  end

  defp auto_matches_percentage(auto_matches), do: length(auto_matches) * 100 / Moba.daily_match_limit()
  defp manual_matches_percentage(manual_matches), do: length(manual_matches) * 100 / Moba.daily_match_limit()
  defp total_win_rate(%{total_matches: 0}), do: 0
  defp total_win_rate(player), do: trunc(player.total_wins * 100 / player.total_matches)

  defp params_to_order(nil), do: []

  defp params_to_order(params) do
    Enum.sort(params, fn {_, v1}, {_, v2} ->
      String.to_integer(v1) <= String.to_integer(v2)
    end)
    |> Enum.map(fn {code, _} -> code end)
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

  defp tier_buff_pct(%{current_immortal_streak: streak}) when streak > 0 do
    Float.round(streak * Moba.immortal_streak_multiplier() * 100, 1)
  end

  defp tier_buff_pct(_), do: nil

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
    do: %{class: "badge badge-pill badge-light-success", label: "+#{points} Season Points"}

  defp rewards_badge(points), do: %{class: "badge badge-pill badge-light-dark", label: "#{points} Season Points"}

  defp duel_label(%{type: "elite_matchmaking"}), do: "Elite MM"
  defp duel_label(%{type: "pvp"}), do: "Duel"
  defp duel_label(_), do: "Normal MM"

  defp duel_badge_class(%{type: "pvp"}), do: "badge badge-light-danger"
  defp duel_badge_class(%{type: "elite_matchmaking"}), do: "badge badge-light-warning"
  defp duel_badge_class(_), do: "badge badge-light-primary"

  defp match_type_label(%{type: "auto"}), do: "A"
  defp match_type_label(_), do: "M"

  defp match_type_title(%{type: "auto"}), do: "Auto Match"
  defp match_type_title(_), do: "Manual Match"

  defp opponent_for(duel, %{id: id}) when duel.player_id == id, do: duel.opponent_player
  defp opponent_for(duel, _player), do: duel.player

  defp ranking_inclusion?(ranking, player), do: Enum.any?(ranking, &(&1.id == player.id))
end
