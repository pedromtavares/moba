defmodule MobaWeb.V2.PlayerLive do
  use MobaWeb, :v2_live_view
  import MobaWeb.CoreComponents, only: [icon: 1]

  embed_templates "player_live/*"

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    socket = user_assigns(id, nil, socket)

    if connected?(socket) do
      MobaWeb.subscribe("player-ranking")
      MobaWeb.subscribe("hero-ranking")
    end

    {:noreply, socket}
  end

  def handle_params(%{"player_id" => id}, _uri, socket) do
    player = Game.get_player!(id)
    socket = user_assigns(player.user_id, player, socket)

    if connected?(socket) do
      MobaWeb.subscribe("player-ranking")
      MobaWeb.subscribe("hero-ranking")
    end

    {:noreply, socket}
  end

  def handle_event("set-featured", %{"id" => id}, socket) do
    {:noreply, assign(socket, featured: Game.get_hero!(id))}
  end

  def handle_event("show-duels", _, %{assigns: %{player: player}} = socket) do
    {:noreply, assign(socket, duels: Game.list_finished_duels(player), filter: "duels")}
  end

  def handle_event("show-matches", _, %{assigns: %{player: player}} = socket) do
    matches = player |> Game.list_matches() |> Enum.filter(&(&1.phase == "scored"))
    {:noreply, assign(socket, matches: matches, filter: "matches")}
  end

  def handle_event("profile-ranking", %{"type" => tab}, socket) when tab in ["season", "hero"] do
    {:noreply, assign(socket, ranking_tab: tab)}
  end

  def handle_event("profile-ranking", %{"type" => "team"}, socket) do
    {:noreply,
     assign(socket, ranking_tab: "team", team_ranking: Game.TeamRuns.ranking(socket.assigns.best_team_rank[:id]))}
  end

  def handle_info({"ranking", _}, %{assigns: %{player: %{id: id}}} = socket) do
    player = Game.get_player!(id)
    heroes = ranked_heroes()
    best = Enum.find(heroes, &(&1.player_id == player.id))
    best_team = best_team_rank(player.id)
    matches = player |> Game.list_matches() |> Enum.filter(&(&1.phase == "scored"))
    duels = Game.list_finished_duels(player)
    first_battle? = socket.assigns.matches == [] && socket.assigns.duels == []
    socket = assign_collection(socket, player, socket.assigns.featured)

    {:noreply,
     assign(socket,
       ranking: Moba.season_ranking(),
       hero_ranking: heroes,
       best_ranked_hero_id: best && best.id,
       best_hero_rank: Game.best_hero_rank(player.id),
       best_team_rank: best_team,
       team_ranking: if(socket.assigns.ranking_tab == "team", do: Game.TeamRuns.ranking(best_team[:id])),
       player: player,
       recent_results: Game.Matches.recent_results(player),
       matches: matches,
       duels: duels,
       filter: if(first_battle?, do: initial_history_tab(matches, duels), else: socket.assigns.filter),
       arena_debut: if(matches == [] && duels == [], do: arena_debut(player, socket.assigns.featured))
     )}
  end

  defp ranked_heroes do
    Moba.pve_ranking()
    |> Enum.filter(&(&1.pve_ranking in 1..Moba.pve_ranking_limit()))
    |> Enum.sort_by(& &1.pve_ranking)
  end

  defp best_team_rank(player_id), do: Game.TeamRuns.best_ranks_for_players([player_id])[player_id]

  defp assign_collection(socket, player, selected \\ nil) do
    collection =
      (player.hero_collection || [])
      |> Enum.map(fn entry ->
        entry
        |> Map.get("profile", entry)
        |> Map.put("avatar_name", get_in(entry, ["avatar", "name"]))
      end)
      |> Enum.sort_by(& &1["position"])

    codes = MapSet.new(collection, & &1["code"])
    blank = Enum.reject(Game.list_avatars(), &MapSet.member?(codes, &1.code))

    featured =
      cond do
        selected && Enum.any?(collection, &(&1["hero_id"] == selected.id)) -> selected
        collection != [] -> List.first(Game.get_heroes([hd(collection)["hero_id"]])) || player.current_pve_hero
        true -> player.current_pve_hero
      end

    assign(socket, profile_collection: collection, blank_collection: blank, featured: featured)
  end

  defp user_assigns(user_id, cached_player, %{assigns: %{current_player: current_player}} = socket) do
    user = Accounts.get_user!(user_id)
    player = cached_player || Moba.player_for(user)
    socket = assign_collection(socket, player)
    duels = Game.list_finished_duels(player)
    matches = player |> Game.list_matches() |> Enum.filter(&(&1.phase == "scored"))
    ranking = Moba.season_ranking()
    hero_ranking = ranked_heroes()
    best = Enum.find(hero_ranking, &(&1.player_id == player.id))
    sidebar_code = if player.id == current_player.id, do: "user", else: nil

    assign(socket,
      duels: duels,
      filter: initial_history_tab(matches, duels),
      matches: matches,
      player: player,
      recent_results: Game.Matches.recent_results(player),
      ranking: ranking,
      hero_ranking: hero_ranking,
      best_ranked_hero_id: best && best.id,
      best_hero_rank: Game.best_hero_rank(player.id),
      best_team_rank: best_team_rank(player.id),
      team_ranking: nil,
      arena_debut: if(matches == [] && duels == [], do: arena_debut(player, socket.assigns.featured)),
      ranking_tab: "season",
      sidebar_code: sidebar_code,
      user: user
    )
  end

  defp initial_history_tab([], [_ | _]), do: "duels"
  defp initial_history_tab(_, _), do: "matches"

  defp arena_debut(%{current_pve_hero: %{finished_at: nil} = hero}, _featured) do
    %{state: :training, hero: hero, action: "Continue training", path: ~p"/training"}
  end

  defp arena_debut(player, featured) do
    case Game.trained_pvp_heroes(player.id, [], 1) do
      [hero] ->
        %{state: :ready, hero: hero, action: "Enter Arena", path: ~p"/arena"}

      [] ->
        %{state: :train, hero: player.current_pve_hero || featured, action: "Train a new hero", path: ~p"/new"}
    end
  end

  defp in_ranking?(ranking, %{id: id}) do
    ranking
    |> Enum.map(& &1.id)
    |> Enum.member?(id)
  end

  defp opponent_for(duel, %{id: id}) when duel.player_id == id, do: duel.opponent_player
  defp opponent_for(duel, _), do: duel.player

  defp registration_age(player) do
    time = if player.user, do: player.user.inserted_at, else: player.inserted_at
    now = Timex.now()

    Enum.find_value([years: "year", months: "month", days: "day", hours: "hour", minutes: "minute"], fn {unit, label} ->
      age = max(Timex.diff(now, time, unit), 0)

      if age > 0 || unit == :minutes do
        {age, if(age == 1, do: label, else: label <> "s")}
      end
    end)
  end

  defp registered_label(player) do
    time = if player.user, do: player.user.inserted_at, else: player.inserted_at
    formatted = time |> Timex.format("{relative}", :relative) |> elem(1)

    cond do
      player.bot_options -> "A.I. Player"
      player.user -> "Registered #{formatted}"
      true -> "Joined #{formatted}"
    end
  end

  defp season_score(player), do: Game.season_score(player)

  defp shadow_rank(%{ranking: 1, pvp_tier: tier}), do: tier + 1
  defp shadow_rank(%{pvp_tier: tier}), do: tier

  defp arena_bracket(%{pvp_tier: 2}), do: "Immortals"
  defp arena_bracket(%{pvp_tier: 1}), do: "Shadows"
  defp arena_bracket(_), do: "Plebs"

  defp featured_hero_card(assigns) do
    ~H"""
    <div id={"hero_#{@hero.id}"}>
      <.link
        class="hero-card card mb-0"
        style={"background-image: url(#{GH.background_url(@hero)})"}
        navigate={preview_path(assigns, ~p"/hero/#{@hero}")}
      >
        <h4 class="card-header text-white d-flex justify-content-between align-items-center mb-0 py-2">
          <span class="font-italic f-rpg font-16 hero-card-rank">
            <%= if @hero.pve_ranking do %>
              #{@hero.pve_ranking}
            <% end %>
          </span>
          <div class="font-15 hero-card-name">
            <.league_badge tier={@hero.league_tier} variant="legacy" />
            {@hero.name}
          </div>
          <span
            class="font-15 font-italic hero-card-meta"
            data-toggle="tooltip"
            title={TT.hero_stats_tooltip(@hero, true)}
          >
            Level {@hero.level} {@hero.avatar.name}
          </span>
        </h4>
        <div class="card-body text-center"></div>
        <div class="transparent card-footer p-0 text-center">
          <div class="row">
            <div class="col-12 mt-1">
              <.hero_skill_strip skills={@hero.skills} id_prefix="skill" id_suffix={@hero.id} />
              <.hero_item_strip items={Game.sort_items(@hero.items)} id_prefix="item" id_suffix={@hero.id} />
            </div>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  defp history_result(nil, _player_id), do: "Tie"
  defp history_result(player_id, player_id), do: "Victory"
  defp history_result(_winner_id, _player_id), do: "Defeat"

  defp duel_rating(%{player_id: player_id, rewards: rewards}, player_id), do: rewards.attacker_pvp_points
  defp duel_rating(duel, _player_id), do: duel.rewards.defender_pvp_points
end
