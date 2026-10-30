defmodule MobaWeb.V2.CommunityLive do
  use MobaWeb, :v2_live_view

  alias Moba.Admin
  alias Moba.Game.CommunityActivity
  alias MobaWeb.Presence
  import MobaWeb.CoreComponents, only: [icon: 1]

  def mount(_, _session, socket) do
    %{assigns: %{channel: channel}} = socket = socket_init(socket)

    socket =
      if connected?(socket) do
        MobaWeb.subscribe(channel)
        MobaWeb.subscribe("stats")
        MobaWeb.subscribe("online")
        Process.send_after(self(), :refresh_recent_players, 30_000)
        tick_user(socket, socket.assigns.current_user)
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

  def handle_event("create-message", params, %{assigns: %{current_player: %{user: user} = player}} = socket) do
    body = params["message"]["body"]
    length = String.length(body)

    if length > 1 && length <= 500 do
      Accounts.create_message!(%{
        body: body,
        author: user.username,
        tier: player.pve_tier,
        channel: "community",
        topic: "general",
        is_admin: user.is_admin,
        user_id: user.id
      })

      {:noreply,
       socket
       |> assign(form: to_form(Accounts.change_message()))
       |> push_event("community-message-sent", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("create-update", params, %{assigns: %{current_user: user}} = socket) do
    if user.is_admin do
      Accounts.create_message!(%{
        title: params["message"]["title"],
        body: params["message"]["body"],
        author: user.username,
        channel: "community",
        topic: "updates",
        is_admin: true,
        user_id: user.id
      })

      {:noreply,
       socket
       |> assign(form: to_form(Accounts.change_message()))
       |> push_event("community-update-sent", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "delete-message",
        %{"id" => id},
        %{assigns: %{current_user: user, messages: messages, updates: updates}} = socket
      ) do
    message = Accounts.get_message!(id)

    if user.is_admin do
      Accounts.delete_message(message)
      {:noreply, assign(socket, messages: messages -- [message], updates: updates -- [message])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("user-filter", %{"period" => period}, %{assigns: %{current_user: %{is_admin: true}}} = socket)
      when period in ["daily", "weekly"] do
    new_filter = if period == "daily", do: :daily, else: :weekly
    {:noreply, assign(socket, user_filter: new_filter) |> stats_assigns()}
  end

  def handle_event("match-filter", %{"type" => filter}, %{assigns: %{current_user: %{is_admin: true}}} = socket)
      when filter in ["pvp", "plebs", "elite"] do
    {:noreply, assign(socket, match_filter: filter) |> stats_assigns()}
  end

  def handle_event("toggle-admin", _, %{assigns: %{current_user: %{is_admin: true}}} = socket) do
    {:noreply, assign(socket, is_admin: !socket.assigns.is_admin)}
  end

  def handle_event(event, _, socket) when event in ["user-filter", "match-filter", "toggle-admin"],
    do: {:noreply, socket}

  def handle_info({"server", _}, socket) do
    {:noreply, stats_assigns(socket)}
  end

  def handle_info({"general", message}, %{assigns: %{messages: messages, current_player: player}} = socket) do
    {:noreply, assign(socket, messages: messages ++ [message]) |> tick_user(player.user)}
  end

  def handle_info({"updates", message}, %{assigns: %{updates: updates}} = socket) do
    {:noreply, assign(socket, updates: [message] ++ updates)}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, live_player_ids: live_player_ids())}
  end

  def handle_info(:refresh_recent_players, socket) do
    Process.send_after(self(), :refresh_recent_players, 30_000)
    {:noreply, assign(socket, players: Moba.recent_community_players(), live_player_ids: live_player_ids())}
  end

  # Private function components

  defp player_card(assigns) do
    ~H"""
    <div class="col-lg-4 col-md-6" id={"player-card-#{@player.id}"}>
      <.link
        class="hero-card card mb-3"
        style={"background-image: url(#{GH.background_url(@player.top_hero)})"}
        navigate={preview_path(assigns, ~p"/player/#{@player.id}")}
      >
        <div class="card-header pt-0 pb-1" style="background:rgba(0,0,0,0.8)">
          <h4 class="text-white d-flex justify-content-between align-items-center mb-0">
            <span class="font-italic f-rpg hero-card-rank" style="font-size: 30px;">#{@player.season_ranking}</span>
            <div class="f-rpg hero-card-name">
              <img src={"/images/pve/#{@player.pve_tier}.png"} style="max-height: 40px" />
              {@player.user.username}
            </div>
            <div class="btn-group hero-card-summary">
              <div
                class="f-rpg text-white"
                data-toggle="tooltip"
                title={"Season Score Calculation: Training Rank (#{@player.pve_tier}) x 100 + Best Immortal Streak (#{@player.best_immortal_streak}) x 100 + Season Points (#{@player.pvp_points})"}
              >
                <i class="ui-icon ui-globe"></i>
                {player_season_score(@player)}
              </div>
            </div>
          </h4>
        </div>
        <div class="card-body p-0 d-flex align-items-center justify-content-center"></div>
        <div class="card-footer transparent p-1" style="background:rgba(0,0,0,0.8)">
          <div class="row">
            <div class="col justify-content-center d-flex hero-card-stats">
              <div class="btn-group hero-stats">
                <.hero_stat_button tone="info" icon="ui-icon ui-focus" title="Season Points" value={@player.pvp_points} />
                <.hero_stat_button
                  tone="danger"
                  icon="ui-icon ui-swords"
                  title="Total Arena Win Rate"
                  value={player_total_win_rate(@player)}
                />
                <.hero_stat_button
                  tone="warning"
                  icon="ui-icon ui-trophy"
                  title="Best Immortal Streak"
                  value={@player.best_immortal_streak}
                />
              </div>
            </div>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  defp pve_hero_card(assigns) do
    ~H"""
    <div class="col-lg-4 col-md-6">
      <.link
        class="hero-card card mb-3"
        style={"background-image: url(#{GH.background_url(@hero)})"}
        navigate={preview_path(assigns, ~p"/hero/#{@hero}")}
      >
        <div class="card-header pt-0 pb-1" style="background:rgba(0,0,0,0.8)">
          <h4 class="text-white d-flex justify-content-between align-items-center mb-0">
            <span class="font-italic f-rpg hero-card-rank" style="font-size: 30px;">#{@hero.pve_ranking}</span>
            <div class="hero-card-name" data-toggle="tooltip" title={"Level #{@hero.level} #{@hero.avatar.name}"}>
              <img src={"/images/pve/#{@hero.player.pve_tier}.png"} style="max-height: 40px" />
              {@hero.name}
            </div>
            <div class="btn-group hero-card-summary">
              <span
                tabindex="0"
                class="game-stat btn btn-icon btn-outline-light text-white"
                data-toggle="tooltip"
                title={"Total farm: #{@hero.total_xp_farm + @hero.total_gold_farm}. Gold farm: #{@hero.total_gold_farm}. XP farm: #{@hero.total_xp_farm}<br/>"}
              >
                <i class="ui-icon ui-crown"></i>
                {GH.farming_amount_label(@hero.total_xp_farm + @hero.total_gold_farm)}
              </span>
              <span
                tabindex="0"
                class="game-stat btn btn-icon btn-outline-light text-white"
                data-toggle="tooltip"
                title="Time it took to finish Training"
              >
                <i class="ui-icon ui-clock"></i>
                {GH.minutes_label(GH.finished_time(@hero), @preview)} min
              </span>
            </div>
          </h4>
        </div>
        <div class="card-body p-0 d-flex align-items-center justify-content-center"></div>
        <div class="card-footer transparent p-1">
          <div class="row">
            <div class="col justify-content-center d-flex hero-card-stats">
              <.hero_stat_group hero={@hero} />
            </div>
          </div>
          <div class="row mt-1">
            <div class="col-12">
              <.hero_skill_strip skills={@hero.skills} id_prefix="skill" id_suffix={@hero.id} />
              <.hero_item_strip
                items={Game.sort_items(@hero.items)}
                container_class="items-container row no-gutters float-right"
                id_prefix="item"
                id_suffix={@hero.id}
              />
            </div>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  defp arena_stats(assigns) do
    ~H"""
    <div id={"community-balance-#{@key}-#{@side}"} class="community-arena-stats-list">
      <table class="community-arena-stats-table">
        <caption class="sr-only">{@title}</caption>
        <tbody>
          <tr :for={{record, {winrate, total, diff}} <- @records} id={"community-#{@key}-#{@side}-#{record.id}"}>
            <td><img src={GH.image_url(record)} alt="" /></td>
            <td>
              <h4>{record.name}</h4>
            </td>
            <td>
              <h3 class={winrate_class(diff, @match_filter)}>{round(winrate)}%<small>({total})</small></h3>
            </td>
          </tr>
        </tbody>
      </table>
      <p :if={@records == []} class="community-balance-empty">No appearances recorded.</p>
    </div>
    """
  end

  defp guest(assigns) do
    assigns = assign(assigns, :hero, assigns.player.current_pve_hero)

    ~H"""
    <article id={"guest-#{@player.id}"} class="community-guest-card" data-current={to_string(@current)}>
      <header>
        <strong>{if @current, do: "You", else: "Guest"}<small>#{@player.id}</small></strong>
        <span class="community-guest-level">
          <img src={"/images/league/#{@hero.league_tier}.png"} alt={GH.league_name(@hero.league_tier)} />Lv {@hero.level}
        </span>
      </header>
      <div class="community-guest-hero" data-fallen={to_string(@hero.pve_state == "dead")}>
        <img src={GH.image_url(@hero.avatar)} alt={@hero.avatar.name} />
        <strong>{@hero.avatar.name}</strong>
      </div>
      <div class="community-guest-loadout">
        <div class="community-guest-skills" aria-label="Skills">
          <img :for={skill <- @hero.skills} src={GH.image_url(skill)} alt={skill.name} title={skill.name} />
        </div>
        <div :if={@hero.items != []} class="community-guest-items" aria-label="Items">
          <img :for={item <- @hero.items} src={GH.image_url(item)} alt={item.name} title={item.name} />
        </div>
      </div>
      <footer>
        <span>Joined {relative_time(@player.inserted_at)}</span><span>{length(@player.hero_collection)} collected</span>
      </footer>
    </article>
    """
  end

  defp player_row(assigns) do
    assigns =
      assign(assigns,
        activity: Map.get(assigns.player, :recent_activity),
        best_hero: Map.get(assigns.player, :best_ranked_hero)
      )

    ~H"""
    <tr id={"user-#{@player.id}"} class="community-player-row" data-current={to_string(@current)}>
      <td class="community-player-cell">
        <div class="community-player-summary">
          <div class="community-player-identity">
            <.link
              navigate={preview_path(assigns, ~p"/player/#{@player.id}")}
              aria-label={"View #{@player.user.username}'s profile"}
            >
              <img src={"/images/pve/#{@player.pve_tier}.png"} alt="" class="community-player-emblem" />
            </.link>
            <span>
              <strong>
                <.link navigate={preview_path(assigns, ~p"/player/#{@player.id}")}>{@player.user.username}</.link><small :if={
                  @current
                }>You</small>
              </strong>
              <span class="community-player-meta">
                <time datetime={@player.user.last_online_at && DateTime.to_iso8601(@player.user.last_online_at)}>
                  Active {relative_time(@player.user.last_online_at)}
                </time>
                <.link
                  :if={@live}
                  navigate={preview_path(assigns, ~p"/arena")}
                  class="community-player-live"
                  aria-label={"#{@player.user.username} is accepting live 1v1 challenges"}
                >
                  <.icon name="game-swords" />Live 1v1
                </.link>
              </span>
            </span>
          </div>
          <div :if={@player.season_ranking || @best_hero} class="community-player-ranks" aria-label="Player accomplishments">
            <.link
              :if={@player.season_ranking}
              navigate={preview_path(assigns, ~p"/player/#{@player.id}")}
              class="community-season-rank"
              aria-label={"Season rank #{@player.season_ranking}"}
            >
              <span>Season</span><strong>#{@player.season_ranking}</strong>
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
        </div>
      </td>
      <td class="community-player-activity">
        <%= if @activity do %>
          <.link
            navigate={preview_path(assigns, activity_path(@activity))}
            class="community-activity-link"
            data-result={Map.get(@activity, :result)}
          >
            <span class="community-activity-icon"><.icon name={activity_icon(@activity)} /></span>
            <span>
              <strong>{activity_title(@activity)}</strong>
              <small>
                {activity_detail(@activity)} <span aria-hidden="true">·</span>
                <time datetime={DateTime.to_iso8601(@activity.at)}>{relative_time(@activity.at)}</time>
              </small>
            </span>
            <span class="community-activity-arrow" aria-hidden="true">↗</span>
          </.link>
        <% else %>
          <span class="community-activity-empty">No recent activity</span>
        <% end %>
      </td>
      <td class="community-player-heroes">
        <div class="community-hero-strip">
          <.link
            :for={hero <- Enum.take(@player.latest_heroes, 6)}
            navigate={preview_path(assigns, ~p"/hero/#{hero}")}
            class="community-recent-hero"
            data-undefeated={to_string(Game.max_farm?(hero))}
            aria-label={"#{hero.avatar.name}, level #{hero.level}#{if Game.max_farm?(hero), do: ", undefeated", else: ""}"}
          >
            <img src={GH.image_url(hero.avatar)} alt={hero.avatar.name} class="community-hero-portrait" />
            <strong :if={hero.pve_ranking} class="community-hero-rank" aria-label={"Hero rank #{hero.pve_ranking}"}>
              #{hero.pve_ranking}
            </strong>
            <span>
              <img src={"/images/league/#{hero.league_tier}.png"} alt={GH.league_name(hero.league_tier)} />Lv {hero.level}
            </span>
          </.link>
          <span :if={@player.latest_heroes == []} class="community-activity-empty">No heroes yet</span>
        </div>
      </td>
    </tr>
    """
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

  defp activity_path(%{kind: kind, id: id}) when kind in [:training_started, :training_finished], do: ~p"/hero/#{id}"
  defp activity_path(%{kind: :match, id: id}), do: ~p"/matches/#{id}"
  defp activity_path(%{id: id}), do: ~p"/arena/#{id}"

  defp activity_icon(%{kind: :training_started}), do: "game-magic"
  defp activity_icon(%{kind: :training_finished}), do: "game-trophy"
  defp activity_icon(%{kind: :match}), do: "game-strategy"
  defp activity_icon(_), do: "game-swords"

  defp activity_title(%{kind: :training_started}), do: "Started training"
  defp activity_title(%{kind: :training_finished}), do: "Finished training"

  defp activity_title(%{kind: kind, result: result}) do
    mode =
      case kind do
        :match -> "5v5"
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
  defp activity_detail(%{opponent: opponent}), do: "vs #{opponent}"

  defp live_player_ids do
    Presence.list("online")
    |> Enum.flat_map(fn {_id, %{metas: metas}} -> Enum.map(metas, & &1.player_id) end)
    |> CommunityActivity.live_player_ids()
  end

  # Private helper functions

  defp formatted_body(%{body: body}) do
    body
    |> PhoenixHTMLHelpers.Format.text_to_html([])
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(
      ~r/https:\/\/browsermoba.com\/battles\/([0-9]+)/,
      "<a href='/battles/\\1' class='text-primary'>Battle #\\1</span>"
    )
    |> Phoenix.HTML.raw()
  end

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

  defp player_season_score(player), do: 100 * player.best_immortal_streak + 100 * player.pve_tier + player.pvp_points

  defp load_ranking(%{assigns: %{pvp_ranking: nil}} = socket, "pvp") do
    assign(socket, pvp_ranking: Moba.season_ranking() |> Enum.filter(& &1.top_hero) |> Enum.take(30))
  end

  defp load_ranking(%{assigns: %{pve_ranking: nil}} = socket, "pve") do
    assign(socket, pve_ranking: Moba.pve_ranking() |> Enum.take(30))
  end

  defp load_ranking(socket, _), do: socket

  defp player_total_win_rate(%{total_matches: matches, total_wins: wins}) when matches > 0 do
    "#{round(wins / matches * 100)}%"
  end

  defp player_total_win_rate(_), do: "0%"

  defp socket_init(%{assigns: %{current_player: %{user: user}}} = socket) do
    channel = "community"
    messages = Accounts.latest_messages(channel, "general", 20) |> Enum.reverse()
    updates = Accounts.latest_messages(channel, "updates", 20)

    assign(socket,
      active_tab: "online",
      form: to_form(Accounts.change_message()),
      channel: channel,
      pve_ranking: nil,
      messages: messages,
      sidebar_code: channel,
      updates: updates,
      pvp_ranking: nil,
      current_user: user,
      notifications: 0
    )
    |> stats_assigns()
  end

  defp tick_user(socket, nil), do: socket

  defp tick_user(socket, user) do
    user = Accounts.update_user!(user, %{community_seen_at: DateTime.utc_now()})
    assign(socket, user: user)
  end

  defp stats_assigns(%{assigns: %{current_player: %{user: user}}} = socket) do
    data = Admin.get_server_data()
    user_filter = socket.assigns[:user_filter] || :weekly
    match_filter = socket.assigns[:match_filter] || "elite"

    assign(socket,
      players: Moba.recent_community_players(),
      live_player_ids: live_player_ids(),
      guests: data.guests,
      user_filter: user_filter,
      user_stats: data.user_stats[user_filter],
      match_filter: match_filter,
      match_stats: data.match_stats[match_filter],
      duels: data.duels,
      is_admin: user && user.is_admin && Map.get(socket.assigns, :is_admin, true)
    )
  end
end
