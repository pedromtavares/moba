defmodule MobaWeb.V2.CommunityLive do
  use MobaWeb, :v2_live_view

  alias Moba.Admin

  def mount(_, _session, socket) do
    %{assigns: %{channel: channel}} = socket = socket_init(socket)

    socket =
      if connected?(socket) do
        MobaWeb.subscribe(channel)
        MobaWeb.subscribe("stats")
        load_rankings(socket)
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("show-online", _, socket) do
    {:noreply, assign(socket, active_tab: "online")}
  end

  def handle_event("show-pvp", _, socket) do
    {:noreply, assign(socket, active_tab: "pvp")}
  end

  def handle_event("show-pve", _, socket) do
    {:noreply, assign(socket, active_tab: "pve")}
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

      {:noreply, assign(socket, form: to_form(Accounts.change_message()))}
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

      {:noreply, assign(socket, form: to_form(Accounts.change_message()))}
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

  def handle_event("user-filter", _, %{assigns: %{user_filter: filter}} = socket) do
    new_filter = if filter == :weekly, do: :daily, else: :weekly
    {:noreply, assign(socket, user_filter: new_filter) |> stats_assigns()}
  end

  def handle_event("match-filter", %{"type" => filter}, socket) do
    {:noreply, assign(socket, match_filter: filter) |> stats_assigns()}
  end

  def handle_event("toggle-admin", _, socket) do
    {:noreply, assign(socket, is_admin: !socket.assigns.is_admin)}
  end

  def handle_info({"server", _}, socket) do
    {:noreply, stats_assigns(socket)}
  end

  def handle_info({"general", message}, %{assigns: %{messages: messages, current_player: player}} = socket) do
    {:noreply, assign(socket, messages: messages ++ [message]) |> tick_user(player.user)}
  end

  def handle_info({"updates", message}, %{assigns: %{updates: updates}} = socket) do
    {:noreply, assign(socket, updates: [message] ++ updates)}
  end

  # Private function components

  defp player_card(assigns) do
    ~H"""
    <div class="col-lg-4 col-md-6" id={"player-card-#{@player.id}"}>
      <.link
        class="hero-card card mb-3"
        style={"background-image: url(#{GH.background_url(@player.top_hero)})"}
        navigate={~p"/player/#{@player.id}"}
      >
        <div class="card-header pt-0 pb-1" style="background:rgba(0,0,0,0.8)">
          <h4 class="text-white d-flex justify-content-between align-items-center mb-0">
            <span class="font-italic f-rpg" style="font-size: 30px;">##{@player.season_ranking}</span>
            <div class="f-rpg">
              <img src={"/images/pve/#{@player.pve_tier}.png"} style="max-height: 40px" />
              {@player.user.username}
            </div>
            <div class="btn-group">
              <div
                class="f-rpg text-white"
                data-toggle="tooltip"
                title={"Season Score Calculation: Training Rank (#{@player.pve_tier}) x 100 + Best Immortal Streak (#{@player.best_immortal_streak}) x 100 + Season Points (#{@player.pvp_points})"}
              >
                <i class="fa-thin fa-globe"></i>
                {player_season_score(@player)}
              </div>
            </div>
          </h4>
        </div>
        <div class="card-body p-0 d-flex align-items-center justify-content-center"></div>
        <div class="card-footer transparent p-1" style="background:rgba(0,0,0,0.8)">
          <div class="row">
            <div class="col justify-content-center d-flex">
              <div class="btn-group hero-stats">
                <button class="btn btn-icon btn-outline-dark text-info" data-toggle="tooltip" title="Season Points">
                  <i class="fa fa-arrows-to-dot"></i> {@player.pvp_points}
                </button>
                <button class="btn btn-icon btn-outline-dark text-danger" data-toggle="tooltip" title="Total Arena Win Rate">
                  <i class="fa fa-swords mr-1"></i> {player_total_win_rate(@player)}
                </button>
                <button
                  class="btn btn-icon btn-outline-dark text-warning"
                  data-toggle="tooltip"
                  title="Best Immortal Streak"
                >
                  <i class="fa fa-trophy"></i> {@player.best_immortal_streak}
                </button>
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
        navigate={~p"/hero/#{@hero}"}
      >
        <div class="card-header pt-0 pb-1" style="background:rgba(0,0,0,0.8)">
          <h4 class="text-white d-flex justify-content-between align-items-center mb-0">
            <span class="font-italic f-rpg" style="font-size: 30px;">#{@hero.pve_ranking}</span>
            <div data-toggle="tooltip" title={"Level #{@hero.level} #{@hero.avatar.name}"}>
              <img src={"/images/pve/#{@hero.player.pve_tier}.png"} style="max-height: 40px" />
              {@hero.name}
            </div>
            <div class="btn-group">
              <button
                class="btn btn-icon btn-outline-light text-white"
                data-toggle="tooltip"
                title={"Total farm: #{@hero.total_xp_farm + @hero.total_gold_farm}. Gold farm: #{@hero.total_gold_farm}. XP farm: #{@hero.total_xp_farm}<br/>"}
              >
                <i class="fa fa-crown"></i>
                {GH.farming_amount_label(@hero.total_xp_farm + @hero.total_gold_farm)}
              </button>
              <button
                class="btn btn-icon btn-outline-light text-white"
                data-toggle="tooltip"
                title="Time it took to finish Training"
              >
                <i class="fa fa-clock-o"></i>
                {GH.finished_time(@hero)} min
              </button>
            </div>
          </h4>
        </div>
        <div class="card-body p-0 d-flex align-items-center justify-content-center"></div>
        <div class="card-footer transparent p-1">
          <div class="row">
            <div class="col justify-content-center d-flex">
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
    <table class="table-dark table border m-0">
      <%= for {record, {winrate, total, diff}} <- @records do %>
        <tr id={"#{record.code}-stats-row"}>
          <td>
            <img src={GH.image_url(record)} class="img-border-xs" style="height: 50px" />
          </td>
          <td>
            <h4>{record.name}</h4>
          </td>
          <td>
            <h3 class={[winrate_class(diff, @match_filter), "text-center m-0"]}>
              {round(winrate)}% <br /><small><em>({total})</em></small>
            </h3>
          </td>
        </tr>
      <% end %>
    </table>
    """
  end

  defp guest(assigns) do
    ~H"""
    <div class="col-md-1 col-2" id={"guest-#{@player.id}"}>
      <div class="card">
        <div
          class="card-header border p-0"
          style="background: rgba(0,0,0, 0.1)"
          data-toggle={if @is_admin, do: "tooltip"}
          title={
            if @is_admin,
              do:
                "Created #{@player.inserted_at |> Timex.format("{relative}", :relative) |> elem(1)}.<br/>Total heroes: #{length(@player.hero_collection)}"
          }
        >
          <h5 class="f-rpg">{if @current, do: "YOU", else: "GUEST"}</h5>
        </div>
        <div class="card-body p-1 border" style="border-radius: 0">
          <img src={GH.image_url(@player.current_pve_hero.avatar)} style="width: 100%" class="img-border-xs" /><br />
          <h5 class="text-white text-center">
            <img src={"/images/league/#{@player.current_pve_hero.league_tier}.png"} style="width: 20px;" /> Lv
            <span class={if @player.current_pve_hero.pve_state == "dead", do: "text-muted"}>
              {@player.current_pve_hero.level}
            </span>
          </h5>
          <div>
            <%= for skill <- @player.current_pve_hero.skills do %>
              <img src={GH.image_url(skill)} style="width: 20%" />
            <% end %>
          </div>
          <div>
            <%= for item <- @player.current_pve_hero.items do %>
              <img src={GH.image_url(item)} style="width: 20%" />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp player_row(assigns) do
    ~H"""
    <tr id={"user-#{@player.id}"} style={if @current, do: "background: rgba(255,255,255, 0.02)"}>
      <td class="text-center cursor-pointer border" phx-click={JS.navigate(~p"/player/#{@player.id}")}>
        <span
          class="text-white"
          data-toggle={if @is_admin, do: "tooltip"}
          title={
            if @is_admin,
              do: "Online #{@player.user.last_online_at |> Timex.format("{relative}", :relative) |> elem(1)}<br/>
                Registered #{@player.user.inserted_at |> Timex.format("{relative}", :relative) |> elem(1)}<br/>
                Total heroes: #{@player.hero_count}"
          }
        >
          <img
            src={"/images/pve/#{@player.pve_tier}.png"}
            class={"rank-shadow-#{player_shadow_rank(@player)}"}
            style="max-height: 50px;"
          />
          <br />
          <h5 class={"text-white rank-shadow-#{player_shadow_rank(@player)} mb-1"}>{@player.user.username}</h5>
          <.status_pill player={@player} />
        </span>
      </td>
      <td class="text-center cursor-pointer border" phx-click={JS.navigate(~p"/player/#{@player.id}")}>
        <h2 class="f-rpg text-danger">
          <%= if @player.ranking do %>
            #{@player.ranking}
          <% else %>
            ?
          <% end %>
        </h2>
        <h4 class={"rank-shadow-#{player_shadow_rank(@player)} f-rpg"}>{arena_tier_label(@player)}</h4>
      </td>
      <td>
        <div class="d-flex justify-content-start">
          <%= for hero <- @player.latest_heroes do %>
            <div class="col-2">
              <.link navigate={~p"/hero/#{hero}"}>
                <img
                  src={GH.image_url(hero.avatar)}
                  style={"width: 100px; #{if Game.max_farm?(hero), do: "border: 1px solid red; border-radius:2px"}"}
                  class="img-border-xs"
                /><br />
                <h5 class="mb-0 text-center">
                  <img src={"/images/league/#{hero.league_tier}.png"} style="width: 20px;" />
                  <span class="text-white">
                    Lv <span class={if hero.pve_state == "dead", do: "text-muted"}>{hero.level}</span>
                    <%= if hero.pve_ranking do %>
                      <span class="text-success">#{hero.pve_ranking}</span>
                    <% end %>
                  </span>
                </h5>
                <%= if hero.finished_at do %>
                  <span
                    class="text-center text-muted"
                    data-toggle={if @is_admin, do: "tooltip"}
                    title={if @is_admin, do: hero.finished_at |> Timex.format("{relative}", :relative) |> elem(1)}
                  >
                    Trained in {GH.finished_time(hero)} min
                  </span>
                <% else %>
                  <span class="text-center text-muted">{hero.pve_total_turns} turns left</span>
                <% end %>
              </.link>
            </div>
          <% end %>
        </div>
      </td>
    </tr>
    """
  end

  defp status_pill(assigns) do
    last_online_at = assigns.player.user.last_online_at
    time_diff = Timex.diff(Timex.now(), last_online_at, :hours)

    cond do
      time_diff < 1 ->
        ~H"""
        <span class="badge badge-pill badge-light-success">Online</span>
        """

      time_diff < 24 ->
        ~H"""
        <span class="badge badge-pill badge-light-warning">Away</span>
        """

      true ->
        ~H"""
        <span class="badge badge-pill badge-light-danger">Offline</span>
        """
    end
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

    Enum.map(data, fn {record, {winrate, total}} ->
      {record, {winrate, total, winrate - average}}
    end)
  end

  defp player_season_score(player), do: 100 * player.best_immortal_streak + 100 * player.pve_tier + player.pvp_points

  defp load_rankings(socket) do
    assign(socket,
      pvp_ranking: Moba.season_ranking() |> Enum.filter(& &1.top_hero) |> Enum.take(30),
      pve_ranking: Moba.pve_ranking() |> Enum.take(30)
    )
  end

  defp player_shadow_rank(%{ranking: 1, pvp_tier: tier}), do: tier + 1
  defp player_shadow_rank(%{pvp_tier: tier}), do: tier

  defp player_total_win_rate(%{total_matches: matches, total_wins: wins}) when matches > 0 do
    "#{round(wins / matches * 100)}%"
  end

  defp player_total_win_rate(_), do: "0%"

  defp arena_tier_label(%{ranking: nil}), do: "Training"
  defp arena_tier_label(%{pvp_tier: 2}), do: "Immortal"
  defp arena_tier_label(%{pvp_tier: 1}), do: "Shadow"
  defp arena_tier_label(_), do: "Pleb"

  defp socket_init(%{assigns: %{current_player: %{user: user}}} = socket) do
    channel = "community"
    messages = Accounts.latest_messages(channel, "general", 20) |> Enum.reverse()
    updates = Accounts.latest_messages(channel, "updates", 20)

    assign(socket,
      active_tab: "online",
      form: to_form(Accounts.change_message()),
      channel: channel,
      pve_ranking: [],
      messages: messages,
      sidebar_code: channel,
      updates: updates,
      pvp_ranking: [],
      current_user: user,
      notifications: 0
    )
    |> tick_user(user)
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
      players: data.players,
      guests: data.guests,
      user_filter: user_filter,
      user_stats: data.user_stats[user_filter],
      match_filter: match_filter,
      match_stats: data.match_stats[match_filter],
      duels: data.duels,
      is_admin: user && user.is_admin
    )
  end
end
