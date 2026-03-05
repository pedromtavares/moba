defmodule MobaWeb.V2.PlayerLive do
  use MobaWeb, :v2_live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    socket = user_assigns(id, nil, socket)
    if connected?(socket), do: MobaWeb.subscribe("player-ranking")
    {:noreply, socket}
  end

  def handle_params(%{"player_id" => id}, _uri, socket) do
    player = Game.get_player!(id)
    socket = user_assigns(player.user_id, player, socket)
    if connected?(socket), do: MobaWeb.subscribe("player-ranking")
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

  def handle_event("switch-ranking", _, %{assigns: %{ranking_display: display}} = socket) do
    other_display = other_ranking_display(display)
    {:noreply, assign(socket, ranking: ranking_for(other_display), ranking_display: other_display)}
  end

  def handle_info({"ranking", _}, %{assigns: %{player: %{id: id}, ranking_display: display}} = socket) do
    {:noreply, assign(socket, ranking: ranking_for(display), player: Game.get_player!(id))}
  end

  defp featured_hero(%{hero_collection: collection}) when length(collection) > 0 do
    collection |> List.first() |> Map.fetch!("hero_id") |> Game.get_hero!()
  end

  defp featured_hero(player), do: player.current_pve_hero

  defp other_ranking_display("daily"), do: "season"
  defp other_ranking_display(_), do: "daily"

  defp ranking_for("daily"), do: Moba.daily_ranking()
  defp ranking_for(_), do: Moba.season_ranking()

  defp user_assigns(user_id, cached_player, %{assigns: %{current_player: current_player}} = socket) do
    user = Accounts.get_user!(user_id)
    player = cached_player || Moba.player_for(user)
    collection_codes = Enum.map(player.hero_collection, & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))
    featured = featured_hero(player)
    duels = Game.list_finished_duels(player)
    matches = player |> Game.list_matches() |> Enum.filter(&(&1.phase == "scored"))
    ranking_display = "daily"
    ranking = ranking_for(ranking_display)
    sidebar_code = if player.id == current_player.id, do: "user", else: nil

    assign(socket,
      blank_collection: blank_collection,
      duels: duels,
      featured: featured,
      filter: "matches",
      matches: matches,
      player: player,
      ranking: ranking,
      ranking_display: ranking_display,
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
        navigate={~p"/v2/hero/#{@hero}"}
      >
        <h4 class="card-header text-white d-flex justify-content-between align-items-center mb-0 py-2">
          <span class="font-italic f-rpg font-16">
            <%= if @hero.pve_ranking do %>
              ##{@hero.pve_ranking}
            <% end %>
          </span>
          <div class="font-15">
            <img src={"/images/league/#{@hero.league_tier}.png"} class="league-logo" />
            {@hero.name}
          </div>
          <span
            class="font-15 font-italic"
            data-toggle="tooltip"
            title={GH.hero_stats_string(@hero, true)}
          >
            Level {@hero.level} {@hero.avatar.name}
          </span>
        </h4>
        <div class="card-body text-center"></div>
        <div class="transparent card-footer p-0 text-center">
          <div class="row">
            <div class="col-12 mt-1">
              <div class="skills-container d-flex justify-content-between">
                <%= for skill <- @hero.skills do %>
                  <img
                    src={GH.image_url(skill)}
                    class={["skill-img img-border-sm tooltip-mobile", skill.passive && "passive"]}
                    data-toggle="tooltip"
                    title={GH.skill_description(skill)}
                    id={"skill-#{skill.id}-#{@hero.id}"}
                  />
                <% end %>
              </div>
              <div class="items-container row no-gutters">
                <%= for item <- Game.sort_items(@hero.items) do %>
                  <div class="item-container col-4">
                    <img
                      src={GH.image_url(item)}
                      class={["item-img img-border-xs tooltip-mobile", !item.active && "passive"]}
                      data-toggle="tooltip"
                      title={GH.item_description(item)}
                      id={"item-#{item.id}-#{@hero.id}"}
                    />
                  </div>
                <% end %>
              </div>
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
