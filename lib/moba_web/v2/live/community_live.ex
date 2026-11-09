defmodule MobaWeb.V2.CommunityLive do
  use MobaWeb, :v2_live_view

  alias Moba.Admin
  alias Moba.Game.CommunityActivity
  alias MobaWeb.Presence
  alias MobaWeb.V2.Components.TeamComponents
  import MobaWeb.CoreComponents, only: [icon: 1]

  def mount(_, _session, socket) do
    socket = assign_new(socket, :current_scope, fn -> %{user: socket.assigns[:current_user]} end)
    is_admin = match?(%{is_admin: true}, socket.assigns.current_scope.user)

    socket =
      assign(socket,
        active_tab: "online",
        sidebar_code: "community",
        pvp_ranking: nil,
        pve_ranking: nil,
        is_admin: is_admin,
        user_filter: :weekly,
        match_filter: "elite",
        balance_category: :avatars
      )
      |> refresh_players()
      |> stats_assigns()

    socket =
      if connected?(socket) do
        if socket.assigns.is_admin, do: MobaWeb.subscribe("stats")
        MobaWeb.subscribe("online")
        MobaWeb.subscribe("player-ranking")
        Process.send_after(self(), :refresh_recent_players, 30_000)
        socket
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("show-online", _, socket) do
    {:noreply, assign(socket, active_tab: "online")}
  end

  def handle_event("show-pvp", _, socket) do
    {:noreply, socket |> load_ranking("pvp") |> assign(active_tab: "pvp")}
  end

  def handle_event("show-pve", _, socket) do
    {:noreply, socket |> load_ranking("pve") |> assign(active_tab: "pve")}
  end

  def handle_event("show-teams", _, socket) do
    {:noreply, assign(socket, active_tab: "teams", team_ranking: Game.TeamRuns.ranking(nil, 30))}
  end

  def handle_event("show-balance", _, %{assigns: %{is_admin: true}} = socket) do
    {:noreply, assign(socket, active_tab: "balance")}
  end

  def handle_event("balance-category", %{"category" => category}, %{assigns: %{is_admin: true}} = socket)
      when category in ["avatars", "skills", "items"] do
    {:noreply, assign(socket, balance_category: String.to_existing_atom(category))}
  end

  def handle_event("user-filter", %{"period" => period}, %{assigns: %{is_admin: true}} = socket)
      when period in ["daily", "weekly"] do
    new_filter = if period == "daily", do: :daily, else: :weekly
    {:noreply, assign(socket, user_filter: new_filter) |> stats_assigns()}
  end

  def handle_event("match-filter", %{"type" => filter}, %{assigns: %{is_admin: true}} = socket)
      when filter in ["pvp", "plebs", "elite"] do
    {:noreply, assign(socket, match_filter: filter) |> stats_assigns()}
  end

  def handle_event(event, _, socket)
      when event in [
             "user-filter",
             "match-filter",
             "show-pulse",
             "show-balance",
             "balance-category",
             "toggle-admin",
             "create-message",
             "create-update",
             "delete-message"
           ],
      do: {:noreply, socket}

  def handle_info({"server", _}, socket), do: {:noreply, stats_assigns(socket)}

  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, live_player_ids: live_player_ids())}
  end

  def handle_info({"availability", _}, socket) do
    {:noreply, assign(socket, live_player_ids: live_player_ids())}
  end

  def handle_info({"ranking", _}, %{assigns: %{pvp_ranking: nil}} = socket), do: {:noreply, socket}

  def handle_info({"ranking", _}, socket) do
    {:noreply, socket |> assign(pvp_ranking: nil) |> load_ranking("pvp")}
  end

  def handle_info(:refresh_recent_players, socket) do
    Process.send_after(self(), :refresh_recent_players, 30_000)
    {:noreply, refresh_players(socket)}
  end

  # Private function components

  defp player_card(assigns) do
    assigns = assign(assigns, :arena_title, player_card_title(assigns.player))

    ~H"""
    <.player_banner id={"player-card-#{@player.id}"} player={@player} hero={@player.top_hero} preview={@preview} linked>
      <:ranks>
        <span class="community-player-rank">#{@player.season_ranking}</span>
      </:ranks>
      <:summary>
        <span
          id={"player-season-score-#{@player.id}"}
          class="player-season-score"
          data-toggle="tooltip"
          title={TT.season_score_tooltip(@player)}
          tabindex="0"
          aria-label={"#{Game.season_score(@player)} Season Score"}
        >
          <.icon name="game-season-score" /><strong>{Game.season_score(@player)}</strong><small>Season Score</small>
        </span>
      </:summary>
      <:banner_bottom>
        <span :if={@arena_title} class="player-card-arena-title" data-title={@arena_title.key}>
          <.icon name={@arena_title.icon} /><span>{@arena_title.label}</span>
        </span>
      </:banner_bottom>
      <:footer>
        <dl class="player-card-metrics">
          <div data-metric="arena-rating" data-tone="rating">
            <dt><.icon name="game-swords" /><span>Arena Rating</span></dt>
            <dd>{@player.pvp_points}</dd>
          </div>
          <div data-metric="win-rate" data-tone="wins">
            <dt><.icon name="game-arena-3v3" /><span>3v3 win rate</span></dt>
            <dd title={GH.win_rate_summary(@recent_results)}>{GH.win_rate(@recent_results)}%</dd>
          </div>
          <div data-metric="immortal-streak" data-tone="streak">
            <dt><.icon name="game-trophy" /><span>Best Streak</span></dt>
            <dd>{@player.best_immortal_streak}</dd>
          </div>
        </dl>
      </:footer>
    </.player_banner>
    """
  end

  defp player_card_title(%{pvp_tier: 2, ranking: 1}),
    do: %{key: "the-immortal", label: "The Immortal", icon: "game-trophy"}

  defp player_card_title(%{pvp_tier: 2}), do: %{key: "immortals", label: "Immortals", icon: "game-hero"}
  defp player_card_title(%{pvp_tier: 1}), do: %{key: "shadow", label: "Shadow", icon: "game-hero"}
  defp player_card_title(_), do: nil

  attr :entry, :map, required: true
  attr :preview, :boolean, required: true

  defp team_card(assigns) do
    assigns = assign(assigns, :team, assigns.entry.team)

    ~H"""
    <.link
      id={"community-team-#{@team.id}"}
      class="community-player-card community-ranked-card community-team-card"
      data-community-entry
      navigate={preview_path(assigns, ~p"/teams/#{@team.id}")}
    >
      <div class="community-player-banner community-team-banner">
        <header class="community-player-heading">
          <h3 class="community-player-name">
            <img
              src={"/images/league/#{@team.league_tier}.png"}
              alt={Moba.leagues()[@team.league_tier]}
              class="community-player-emblem"
            />
            <strong>{TeamComponents.display_name(@team)}</strong>
          </h3>
          <span class="community-player-rank">#{@entry.position}</span>
        </header>
        <.team_portraits heroes={@team.heroes} />
      </div>
      <footer class="community-ranking-footer">
        <dl class="player-card-metrics community-team-metrics">
          <div data-tone="streak">
            <dt><.icon name="game-gold" /><span>Avg farm</span></dt>
            <dd>{GH.farming_amount_label(div(@team.total_farm, 3))}</dd>
          </div>
          <div data-tone="wins">
            <dt><.icon name="game-clock" /><span>Time</span></dt>
            <dd title={"#{@team.duration_seconds} seconds"}>
              {GH.minutes_label(div(@team.duration_seconds, 60), @preview)} min
            </dd>
          </div>
        </dl>
      </footer>
    </.link>
    """
  end

  attr :heroes, :list, required: true
  attr :show_names, :boolean, default: true
  attr :show_levels, :boolean, default: false

  defp team_portraits(assigns) do
    ~H"""
    <div class="community-team-portraits">
      <div
        :for={hero <- @heroes}
        style={"--team-hero-art: url(#{GH.background_url(hero)})"}
        data-fallen={if Map.get(hero, :fallen), do: "true"}
        role={unless @show_names, do: "img"}
        aria-label={unless @show_names, do: portrait_label(hero, @show_levels)}
      >
        <span :if={@show_names}>{hero.avatar.name}</span>
        <span :if={@show_levels} class="community-guest-level" aria-hidden="true">Lv {hero.level}</span>
      </div>
    </div>
    """
  end

  defp portrait_label(hero, true), do: "#{hero.avatar.name}, level #{hero.level}"
  defp portrait_label(hero, false), do: hero.avatar.name

  attr :hero, :map, required: true
  attr :preview, :boolean, required: true

  defp pve_hero_card(assigns) do
    ~H"""
    <article
      id={"community-hero-#{@hero.id}"}
      class="community-player-card community-ranked-card"
      data-community-entry
      style={"--player-art: url(#{GH.background_url(@hero)})"}
    >
      <div class="community-player-banner">
        <header class="community-player-heading">
          <div class="community-hero-identity">
            <.link
              navigate={preview_path(assigns, ~p"/hero/#{@hero}")}
              class="community-player-name community-player-name-stretched"
            >
              <img
                src={"/images/pve/#{@hero.player.pve_tier}.png"}
                alt={Moba.pve_tiers()[@hero.player.pve_tier]}
                class="community-player-emblem"
              />
              <strong>{@hero.name}</strong>
            </.link>
            <div class="community-hero-meta">
              <span class="community-hero-avatar">{@hero.avatar.name}</span>
              <span aria-hidden="true">·</span>
              <span
                class="community-hero-level tooltip-mobile"
                data-toggle="tooltip"
                title={TT.combat_stats_tooltip(@hero)}
                tabindex="0"
                aria-label={"Level #{@hero.level}, view combat stats"}
              >
                Level {@hero.level}
              </span>
            </div>
          </div>
          <span class="community-player-rank">#{@hero.pve_ranking}</span>
        </header>
      </div>
      <footer class="community-ranking-footer">
        <dl class="player-card-metrics community-hero-metrics">
          <div data-tone="streak">
            <dt><.icon name="game-gold" /><span>Farm</span></dt>
            <dd
              class="tooltip-mobile"
              tabindex="0"
              data-toggle="tooltip"
              title={"#{@hero.total_xp_farm} XP · #{@hero.total_gold_farm} Gold"}
            >
              {GH.farming_amount_label(@hero.total_xp_farm + @hero.total_gold_farm)}
            </dd>
          </div>
          <div data-tone="wins">
            <dt><.icon name="game-clock" /><span>Time</span></dt>
            <dd>{GH.minutes_label(GH.finished_time(@hero), @preview)} min</dd>
          </div>
        </dl>
        <div class="community-hero-build">
          <.hero_skill_strip
            skills={@hero.skills}
            container_class="community-hero-skills"
            id_prefix="skill"
            id_suffix={@hero.id}
          />
          <.hero_item_strip
            :if={@hero.items != []}
            items={Game.sort_items(@hero.items)}
            container_class="community-hero-items"
            item_container_class="community-hero-item"
            id_prefix="item"
            id_suffix={@hero.id}
          />
        </div>
      </footer>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp community_pager(assigns) do
    ~H"""
    <div id={@id} class="community-pager" phx-hook="CommunityPager">
      {render_slot(@inner_block)}
      <nav class="community-pager-controls" aria-label={"#{@label} pages"} hidden>
        <button type="button" data-community-direction="-1" aria-label={"Previous page of #{@label}"}>←</button>
        <span data-community-page-label aria-live="polite"></span>
        <button type="button" data-community-direction="1" aria-label={"Next page of #{@label}"}>→</button>
      </nav>
    </div>
    """
  end

  defp arena_stats(assigns) do
    ~H"""
    <section id={"community-balance-#{@key}-#{@side}"} class="community-arena-stats-list">
      <h3>{@title}</h3>
      <div class="community-balance-entries" data-community-page-group>
        <article
          :for={{record, {winrate, total, diff}} <- @records}
          data-community-entry
          id={"community-#{@key}-#{@side}-#{record.id}"}
        >
          <img src={GH.image_url(record)} alt="" />
          <h4>{record.name}</h4>
          <h3 class={winrate_class(diff, @match_filter)}>{round(winrate)}%<small>({total})</small></h3>
        </article>
        <p :if={@records == []} class="community-balance-empty">No appearances recorded.</p>
      </div>
    </section>
    """
  end

  defp recent_players(assigns) do
    ~H"""
    <.community_pager id={@id <> "-pages"} label={@label}>
      <div id={@id} class="community-recent-grid" data-community-page-group>
        <.recent_player_card
          :for={player <- @players}
          preview={@preview}
          player={player}
          current={player.id == @current_player.id}
          live={MapSet.member?(@live_player_ids, player.id)}
          admin={@admin}
        />
        <.guest
          :for={guest <- @guests}
          guest={guest}
          current={guest.player.id == @current_player.id}
          preview={@preview}
          admin={@admin}
        />
        <p :if={@players == [] && @guests == []} class="community-players-empty">{@empty}</p>
      </div>
    </.community_pager>
    """
  end

  defp guest(assigns) do
    %{player: player, heroes: heroes, last_online_at: last_online_at} = assigns.guest

    rank = "PvE rank: #{Moba.pve_tiers()[player.pve_tier || 0]}"
    tooltip = if assigns.admin, do: "#{rank}<br/>Last online: #{relative_time(last_online_at)}", else: rank

    assigns =
      assign(assigns,
        player: player,
        heroes: heroes,
        solo_hero: if(match?([_], heroes), do: hd(heroes)),
        last_online_at: last_online_at,
        joined_at: DateTime.from_naive!(player.inserted_at, "Etc/UTC"),
        league_tier: Map.get(assigns.guest, :league_tier),
        tooltip: tooltip
      )

    ~H"""
    <.player_banner
      id={"guest-#{@player.id}"}
      player={@player}
      hero={List.first(@heroes)}
      roster={if length(@heroes) > 1, do: @heroes, else: []}
      preview={@preview}
      current={@current}
      guest_name={if @current, do: "You", else: "Guest ##{@player.id}"}
    >
      <:summary>
        <span class="community-player-status" data-activity={activity_recency(@last_online_at)}>
          <span class="community-status-dot" aria-hidden="true"></span>
          {activity_status(@last_online_at)}
        </span>
      </:summary>
      <:banner_bottom>
        <span :if={@solo_hero} class="community-guest-solo-caption">
          {@solo_hero.avatar.name} <span class="community-guest-level">Lv {@solo_hero.level}</span>
        </span>
      </:banner_bottom>
      <:footer>
        <div class="community-activity-link tooltip-mobile" data-toggle="tooltip" tabindex="0" title={@tooltip}>
          <.activity_metrics
            label={if is_integer(@league_tier), do: "#{GH.league_name(@league_tier)} League"}
            at={@joined_at}
            time_label="Joined"
          >
            <:emblem :if={is_integer(@league_tier)}>
              <img class="community-guest-league-emblem" src={"/images/league/#{@league_tier}.png"} alt="" />
            </:emblem>
          </.activity_metrics>
        </div>
      </:footer>
    </.player_banner>
    """
  end

  defp recent_player_card(assigns) do
    assigns =
      assign(assigns,
        activity: Map.get(assigns.player, :recent_activity),
        best_hero: Map.get(assigns.player, :best_ranked_hero),
        best_team: Map.get(assigns.player, :best_ranked_team)
      )

    ~H"""
    <.player_banner
      id={"user-#{@player.id}"}
      player={@player}
      hero={Map.get(@player, :latest_hero)}
      roster={get_in(@player, [Access.key(:latest_training_team), :heroes]) || []}
      preview={@preview}
      current={@current}
    >
      <:summary>
        <div class="community-player-meta">
          <span
            class="community-player-status"
            data-activity={activity_recency(@player.user.last_online_at)}
            data-toggle={if @admin, do: "tooltip"}
            title={if @admin, do: player_activity_tooltip(@player.user)}
            tabindex={if @admin, do: "0"}
          >
            <span class="community-status-dot" aria-hidden="true"></span>
            {activity_status(@player.user.last_online_at)}
          </span>
          <.link
            :if={@live}
            navigate={preview_path(assigns, ~p"/arena")}
            class="community-player-live"
            aria-label={"#{@player.user.username} is accepting live 1v1 challenges"}
          >
            <.icon name="game-swords" />Live 1v1
          </.link>
        </div>
      </:summary>
      <:ranks>
        <div
          :if={@player.season_ranking || @best_team || @best_hero}
          class="community-player-ranks"
          aria-label="Player accomplishments"
        >
          <.link
            :if={@player.season_ranking}
            navigate={preview_path(assigns, ~p"/player/#{@player.id}")}
            data-profile-username={Moba.Utils.username(@player)}
            class="community-season-rank"
            aria-label={"Season rank #{@player.season_ranking}"}
          >
            <span>Season</span><strong>#{@player.season_ranking}</strong>
          </.link>
          <.link
            :if={@best_team}
            navigate={preview_path(assigns, ~p"/teams/#{@best_team.id}")}
            class="community-best-team-rank"
            aria-label={"Best team rank #{@best_team.position}"}
          >
            <span>Team</span><strong>#{@best_team.position}</strong>
          </.link>
          <.link
            :if={@best_hero}
            navigate={preview_path(assigns, ~p"/hero/#{@best_hero.id}")}
            class="community-best-hero-rank"
            aria-label={"Best hero rank #{@best_hero.pve_ranking}, #{@best_hero.avatar.name}"}
          >
            <span>Hero</span><strong>#{@best_hero.pve_ranking}</strong>
          </.link>
        </div>
      </:ranks>
      <:footer :if={@activity}>
        <.recent_activity activity={@activity} preview={@preview} />
      </:footer>
    </.player_banner>
    """
  end

  attr :activity, :map, required: true
  attr :preview, :boolean, required: true

  defp recent_activity(assigns) do
    assigns = assign(assigns, :path, activity_path(assigns.activity))
    assigns = assign(assigns, :result, Map.get(assigns.activity, :result))

    ~H"""
    <.activity_container path={@path} preview={@preview} result={@result}>
      <.activity_metrics label={activity_title(@activity)} detail={activity_detail(@activity)} at={@activity.at}>
        <:emblem><.icon name={activity_icon(@activity)} /></:emblem>
      </.activity_metrics>
    </.activity_container>
    """
  end

  attr :path, :string, required: true
  attr :preview, :boolean, required: true
  attr :result, :atom, required: true
  slot :inner_block, required: true

  defp activity_container(assigns) do
    ~H"""
    <.link :if={@path} navigate={preview_path(assigns, @path)} class="community-activity-link" data-result={@result}>
      {render_slot(@inner_block)}
      <span class="community-activity-arrow" aria-hidden="true">↗</span>
    </.link>
    <div :if={!@path} class="community-activity-link">{render_slot(@inner_block)}</div>
    """
  end

  attr :label, :string, required: true
  attr :at, :any, required: true
  attr :detail, :string, default: nil
  attr :time_label, :string, default: nil
  slot :emblem

  defp activity_metrics(assigns) do
    ~H"""
    <dl class="player-card-metrics community-team-metrics community-activity-metrics">
      <div :if={@label} data-tone="streak">
        <dt>{render_slot(@emblem)}<strong>{@label}</strong></dt>
        <dd :if={@detail}><small>{@detail}</small></dd>
      </div>
      <div class="community-activity-time" data-tone="wins">
        <dt><.icon name="game-clock" /><span class={unless @time_label, do: "sr-only"}>{@time_label || "Time"}</span></dt>
        <dd><time datetime={DateTime.to_iso8601(@at)}>{relative_time(@at)}</time></dd>
      </div>
    </dl>
    """
  end

  attr :id, :string, required: true
  attr :player, :map, required: true
  attr :hero, :any, required: true
  attr :roster, :list, default: []
  attr :preview, :boolean, required: true
  attr :current, :boolean, default: false
  attr :linked, :boolean, default: false
  attr :guest_name, :string, default: nil
  slot :ranks
  slot :summary, required: true
  slot :banner_bottom
  slot :footer

  defp player_banner(assigns) do
    ~H"""
    <article
      id={@id}
      class={[
        "community-player-card",
        @linked && "community-ranked-card",
        @roster != [] && "community-team-card community-recent-team-card"
      ]}
      data-community-entry
      data-current={to_string(@current)}
      style={if @roster == [], do: "--player-art: url(#{GH.background_url(@hero)})"}
    >
      <div class={["community-player-banner", @roster != [] && "community-team-banner"]}>
        <.team_portraits :if={@roster != []} heroes={@roster} show_names={false} show_levels={not is_nil(@guest_name)} />
        <header class="community-player-heading">
          <div class="community-player-identity">
            <span :if={@guest_name} class="community-player-name">
              <img src={"/images/pve/#{@player.pve_tier || 0}.png"} alt="" class="community-player-emblem" />
              <strong>{@guest_name}</strong>
            </span>
            <.link
              :if={is_nil(@guest_name)}
              navigate={preview_path(assigns, ~p"/player/#{@player.id}")}
              class={["community-player-name", @linked && "community-player-name-stretched"]}
              data-profile-username={Moba.Utils.username(@player)}
            >
              <img
                src={"/images/pve/#{@player.pve_tier}.png"}
                alt={Moba.pve_tiers()[@player.pve_tier]}
                class="community-player-emblem"
              />
              <strong>{@player.user.username}</strong>
            </.link>
            <small :if={@current && is_nil(@guest_name)}>You</small>
          </div>
          {render_slot(@ranks)}
        </header>
        <div class="community-player-summary">{render_slot(@summary)}</div>
        {render_slot(@banner_bottom)}
      </div>
      <footer
        :if={@footer != []}
        class={[
          "community-ranking-footer",
          !@linked && "community-player-activity"
        ]}
      >
        {render_slot(@footer)}
      </footer>
    </article>
    """
  end

  defp activity_recency(nil), do: "offline"
  defp activity_recency(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> activity_recency()

  defp activity_recency(at) do
    seconds = DateTime.diff(DateTime.utc_now(), at)

    cond do
      seconds < 7_200 -> "recent"
      seconds < 86_400 -> "away"
      true -> "offline"
    end
  end

  defp activity_status(at) do
    case activity_recency(at) do
      "recent" -> "Online"
      "away" -> "Away"
      "offline" -> "Offline"
    end
  end

  defp player_activity_tooltip(user) do
    "Last active: #{relative_time(user.last_online_at)}<br/>" <>
      "Registered: #{registration_time(user.inserted_at)}"
  end

  defp registration_time(nil), do: "time unavailable"

  defp registration_time(at) do
    seconds = max(Timex.diff(Timex.now(), at, :seconds), 0)

    units = [{"year", 365 * 86_400}, {"month", 30 * 86_400}, {"day", 86_400}, {"hour", 3_600}, {"minute", 60}]

    case Enum.find(units, fn {_unit, duration} -> seconds >= duration end) do
      nil ->
        "just now"

      {unit, duration} ->
        amount = round(seconds / duration)
        "#{amount} #{unit}#{if amount == 1, do: "", else: "s"} ago"
    end
  end

  defp relative_time(nil), do: "time unavailable"
  defp relative_time(%NaiveDateTime{} = at), do: relative_time(DateTime.from_naive!(at, "Etc/UTC"))

  defp relative_time(at) do
    seconds = max(DateTime.diff(DateTime.utc_now(), at), 0)

    cond do
      seconds < 60 -> "just now"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp activity_path(%{kind: :training_started, team_name: _}), do: nil
  defp activity_path(%{kind: :training_finished, team_name: _, id: id}), do: ~p"/teams/#{id}"
  defp activity_path(%{kind: kind, id: id}) when kind in [:training_started, :training_finished], do: ~p"/hero/#{id}"
  defp activity_path(%{kind: :match, id: id}), do: ~p"/matches/#{id}"
  defp activity_path(%{id: id}), do: ~p"/arena/#{id}"

  defp activity_icon(%{kind: :training_finished}), do: "game-trophy"
  defp activity_icon(%{kind: :training_started, team_name: _}), do: "game-strategy"
  defp activity_icon(%{kind: :training_started}), do: "game-magic"
  defp activity_icon(%{kind: :match}), do: "game-strategy"
  defp activity_icon(_), do: "game-swords"

  defp activity_title(%{kind: :training_started}), do: "Started training"
  defp activity_title(%{kind: :training_finished}), do: "Finished training"

  defp activity_title(%{kind: kind, result: result}) do
    mode =
      case kind do
        :match -> "3v3"
        :season_duel -> "season duel"
        :live_duel -> "live duel"
      end

    case result do
      :won -> "Won a #{mode}"
      :lost -> "Lost a #{mode}"
      :draw -> "Drew a #{mode}"
    end
  end

  defp activity_detail(%{avatar: avatar}), do: avatar
  defp activity_detail(%{team_name: name}), do: name || "3v3 team"
  defp activity_detail(%{opponent: opponent}), do: "vs #{opponent}"

  defp live_player_ids do
    Presence.list("online")
    |> Enum.flat_map(fn {_id, %{metas: metas}} -> Enum.map(metas, & &1.player_id) end)
    |> CommunityActivity.live_player_ids()
  end

  # Private helper functions

  defp bottom_performing(stats, key) do
    limit = if key == :items, do: 6, else: 10

    mapped_stats(stats, key)
    |> Enum.sort_by(fn {_record, {_winrate, _, diff}} -> diff end)
    |> Enum.take(limit)
  end

  defp top_performing(stats, key) do
    limit = if key == :items, do: 6, else: 10

    mapped_stats(stats, key)
    |> Enum.sort_by(fn {_record, {_winrate, _, diff}} -> diff * -1 end)
    |> Enum.take(limit)
  end

  defp winrate_class(diff, "pvp") when diff > 4 or diff < -4, do: "text-danger"
  defp winrate_class(diff, "plebs") when diff > 4 or diff < -4, do: "text-danger"
  defp winrate_class(diff, "elite") when diff > 8 or diff < -8, do: "text-danger"
  defp winrate_class(diff, _) when diff > 10 or diff < -10, do: "text-danger"
  defp winrate_class(diff, "pvp") when diff > 2 or diff < -2, do: "text-warning"
  defp winrate_class(diff, "plebs") when diff > 2 or diff < -2, do: "text-warning"
  defp winrate_class(diff, "elite") when diff > 4 or diff < -4, do: "text-warning"
  defp winrate_class(diff, _) when diff > 5 or diff < -5, do: "text-warning"
  defp winrate_class(_, _), do: "text-success"

  defp mapped_stats(stats, key) do
    data = stats[key]
    average = stats[:winrate]

    data
    |> Enum.map(fn {record, {winrate, total}} ->
      {record, {winrate, total, winrate - average}}
    end)
  end

  defp load_ranking(%{assigns: %{pvp_ranking: nil}} = socket, "pvp") do
    players = Moba.season_ranking() |> Enum.filter(& &1.top_hero) |> Enum.take(30)
    results = Game.Matches.recent_results(Enum.map(players, & &1.id))
    assign(socket, pvp_ranking: players, pvp_recent_results: results)
  end

  defp load_ranking(%{assigns: %{pve_ranking: nil}} = socket, "pve") do
    assign(socket, pve_ranking: Moba.pve_ranking() |> Enum.take(30))
  end

  defp load_ranking(socket, _), do: socket

  defp refresh_players(socket) do
    guests = Moba.recent_community_guests()
    current = socket.assigns.current_player

    guests =
      if is_nil(current.user_id) do
        others = Enum.reject(guests, &(&1.player.id == current.id))
        List.wrap(Admin.current_guest(current.id)) ++ others
      else
        guests
      end

    assign(socket, players: Moba.recent_community_players(), guests: guests, live_player_ids: live_player_ids())
  end

  defp stats_assigns(%{assigns: %{is_admin: true, user_filter: period, match_filter: bracket}} = socket) do
    data = Admin.get_server_data()

    assign(socket,
      user_stats: data.user_stats[period],
      match_stats: data.match_stats[bracket]
    )
  end

  defp stats_assigns(socket), do: socket
end
