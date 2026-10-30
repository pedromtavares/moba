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

  def handle_info({"ranking", _}, %{assigns: %{player: %{id: id}}} = socket) do
    player = Game.get_player!(id)
    heroes = ranked_heroes()
    best = Enum.find(heroes, &(&1.player_id == player.id))

    {:noreply,
     assign(socket,
       ranking: Moba.season_ranking(),
       hero_ranking: heroes,
       best_ranked_hero_id: best && best.id,
       best_hero_rank: Game.best_hero_rank(player.id),
       player: player
     )}
  end

  defp ranked_heroes do
    Moba.pve_ranking()
    |> Enum.filter(&(&1.pve_ranking in 1..Moba.pve_ranking_limit()))
    |> Enum.sort_by(& &1.pve_ranking)
  end

  defp featured_hero(%{hero_collection: collection}) when length(collection) > 0 do
    collection |> List.first() |> Map.fetch!("hero_id") |> Game.get_hero!()
  end

  defp featured_hero(player), do: player.current_pve_hero

  defp user_assigns(user_id, cached_player, %{assigns: %{current_player: current_player}} = socket) do
    user = Accounts.get_user!(user_id)
    player = cached_player || Moba.player_for(user)
    collection_codes = Enum.map(player.hero_collection, & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))
    featured = featured_hero(player)
    duels = Game.list_finished_duels(player)
    matches = player |> Game.list_matches() |> Enum.filter(&(&1.phase == "scored"))
    ranking = Moba.season_ranking()
    hero_ranking = ranked_heroes()
    best = Enum.find(hero_ranking, &(&1.player_id == player.id))
    sidebar_code = if player.id == current_player.id, do: "user", else: nil

    assign(socket,
      blank_collection: blank_collection,
      duels: duels,
      featured: featured,
      filter: "matches",
      matches: matches,
      player: player,
      ranking: ranking,
      hero_ranking: hero_ranking,
      best_ranked_hero_id: best && best.id,
      best_hero_rank: Game.best_hero_rank(player.id),
      ranking_tab: "season",
      sidebar_code: sidebar_code,
      user: user
    )
  end

  defp avatar_class(hero) do
    if hero["total_farm"] == Moba.max_total_farm() do
      "avatar max-farm"
    else
      "avatar"
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

  defp season_score(player) do
    100 * player.best_immortal_streak + 100 * player.pve_tier + player.pvp_points
  end

  defp shadow_rank(%{ranking: 1, pvp_tier: tier}), do: tier + 1
  defp shadow_rank(%{pvp_tier: tier}), do: tier

  defp arena_bracket(%{pvp_tier: 2}), do: "Immortals"
  defp arena_bracket(%{pvp_tier: 1}), do: "Shadows"
  defp arena_bracket(_), do: "Plebs"

  defp total_win_rate(%{total_matches: matches, total_wins: wins}) when matches > 0 do
    "#{round(wins / matches * 100)}%"
  end

  defp total_win_rate(_), do: "0%"

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

  defp rewards_badge(assigns) do
    ~H"""
    <%= if @rewards > 0 do %>
      <span class="badge badge-pill badge-light-success">+{@rewards} Season Points</span>
    <% else %>
      <%= if @rewards < 0 do %>
        <span class="badge badge-pill badge-light-dark">{@rewards} Season Points</span>
      <% end %>
    <% end %>
    """
  end

  defp match_result(assigns) do
    ~H"""
    <%= if @match.phase != "scored" do %>
      <h5>In Progress</h5>
    <% else %>
      <%= if @match.winner_id == @match.player_id do %>
        <h5 class="text-success">Victory</h5>
      <% else %>
        <h5 class="text-muted">Defeat</h5>
      <% end %>
    <% end %>
    """
  end

  defp duel_result(assigns) do
    ~H"""
    <%= cond do %>
      <% @duel.phase != "finished" -> %>
        <h5>In Progress</h5>
      <% is_nil(@duel.winner_player) -> %>
        <h5 class="text-white">Tie</h5>
      <% @duel.winner_player_id == @player_id -> %>
        <h5 class="text-success">Victory</h5>
      <% true -> %>
        <h5 class="text-muted">Defeat</h5>
    <% end %>
    """
  end
end
