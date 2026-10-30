defmodule MobaWeb.V2.CommunityLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    for key <- ["pve_ranking", "season_ranking", "community_players"], do: Cachex.del(:game_cache, key)

    on_exit(fn ->
      for key <- ["pve_ranking", "season_ranking", "community_players"], do: Cachex.del(:game_cache, key)
    end)

    :ok
  end

  test "recent player rows show activity and six heroes without repeating Arena rankings", %{conn: conn} do
    hero = create_base_hero(%{pve_ranking: 15})
    player = Game.update_player!(hero.player, %{season_ranking: 3})
    opponent = create_player!()

    for index <- 1..6 do
      Game.create_hero!(
        %{name: "Recent #{index}", pve_ranking: 20 + index},
        player,
        base_avatar(),
        base_skills()
      )
    end

    match =
      Game.Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        winner_id: player.id,
        phase: "scored",
        type: "manual",
        player_picks: [],
        opponent_picks: [],
        generated_picks: []
      })

    Accounts.set_online_now(player.user)
    cache_recent_players([player.id])
    conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)
    {:ok, view, _} = live(conn, "/community")

    assert has_element?(view, "#community-recent-players th", "Latest activity")
    refute has_element?(view, "#community-recent-players th", "Arena")
    assert has_element?(view, "#user-#{player.id}[data-current=true] .community-player-identity", player.user.username)
    assert has_element?(view, "#user-#{player.id} .community-player-identity time", "Active just now")
    assert has_element?(view, "#user-#{player.id} .community-season-rank", "#3")
    assert has_element?(view, "#user-#{player.id} .community-best-hero-rank[href='/hero/#{hero.id}']", "#15")
    assert has_element?(view, "#user-#{player.id} .community-recent-hero .community-hero-rank", "#26")
    assert has_element?(view, "#user-#{player.id} .community-activity-link[href='/matches/#{match.id}']", "Won a 5v5")

    assert has_element?(
             view,
             "#user-#{player.id} .community-activity-link small",
             Accounts.get_user!(opponent.user_id).username
           )

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#user-#{player.id} .community-recent-hero")
           |> Enum.count() == 6
  end

  test "live indicator requires a connected player accepting challenges", %{conn: conn} do
    hero = create_base_hero()
    live_player = create_player!(%{status: "available"})
    offline_player = create_player!(%{status: "available"})
    Accounts.set_online_now(Accounts.get_user!(live_player.user_id))
    Accounts.set_online_now(Accounts.get_user!(offline_player.user_id))
    MobaWeb.Presence.track_player(self(), live_player)
    cache_recent_players([live_player.id, offline_player.id])

    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")

    assert has_element?(view, "#user-#{live_player.id} .community-player-live[href='/arena']", "Live 1v1")
    refute has_element?(view, "#user-#{offline_player.id} .community-player-live")
    refute has_element?(view, "#user-#{offline_player.id} .community-player-ranks")
    assert has_element?(view, "#user-#{offline_player.id} .community-activity-empty", "No recent activity")

    Game.set_player_unavailable!(live_player)
    send(view.pid, %{event: "presence_diff"})
    refute has_element?(view, "#user-#{live_player.id} .community-player-live")
  end

  test "recent players has an empty state", %{conn: conn} do
    hero = create_base_hero()
    cache_recent_players([])
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")
    assert has_element?(view, "#community-recent-players .community-players-empty", "The hall is quiet")
  end

  test "refreshes recent activity while the community page stays open", %{conn: conn} do
    hero = create_base_hero()
    Accounts.set_online_now(hero.player.user)
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")
    assert has_element?(view, "#user-#{hero.player_id} .community-activity-link", "Started training")

    opponent = create_player!()
    duel = Game.Duels.create!(hero.player, opponent, true)
    Game.Duels.finish!(duel, %{winner: hero.player, attacker_pvp_points: 5, defender_pvp_points: 0})
    Cachex.del(:game_cache, "community_players")
    send(view.pid, :refresh_recent_players)

    assert has_element?(
             view,
             "#user-#{hero.player_id} .community-activity-link[href='/arena/#{duel.id}']",
             "Won a season duel"
           )

    assert has_element?(view, "#show-online-link[aria-selected=true]")
  end

  test "admin pulse follows recent players and Arena Stats keeps the original table information", %{conn: conn} do
    hero = create_base_hero()
    user = hero.player.user |> Ecto.Changeset.change(is_admin: true) |> Moba.Repo.update!()
    unused = Game.get_avatar_by_code!("juggernaut")

    balance = %{
      winrate: 55.0,
      total: 12,
      avatars: %{hero.avatar => {60.0, 20}, unused => {0.0, 0}},
      skills: %{},
      items: %{}
    }

    daily = %{new_guests: 4, new_users: 2, online_today: 5, new_heroes: 10}
    weekly = %{new_guests: 14, new_users: 8, online_today: 20, new_heroes: 30}

    cache_admin_stats(%{daily: daily, weekly: weekly}, %{
      "pvp" => balance,
      "plebs" => %{balance | winrate: 50.0},
      "elite" => balance
    })

    conn = conn |> log_in_user(user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")

    assert has_element?(view, "#community-period-weekly[aria-pressed=true]", "Last 7 days")
    assert has_element?(view, "#community-stat-accounts dd", "8")
    assert has_element?(view, "#community-online > .row:first-child #community-recent-players")
    assert has_element?(view, "#community-online > .row:first-child + #community-admin-summary #community-guests")
    view |> element("#community-period-daily") |> render_click()
    assert has_element?(view, "#community-period-daily[aria-pressed=true]")
    assert has_element?(view, "#community-stat-accounts dd", "2")
    assert has_element?(view, "#community-stat-heroes > span", "2.0 per active player")

    assert has_element?(view, "#community-balance-baseline", "55.0%")
    assert has_element?(view, "#community-arena-stats-title", "Arena Stats")
    assert has_element?(view, "#community-avatars-highest-#{hero.avatar_id} h3.text-warning", "60%")
    assert has_element?(view, "#community-avatars-highest-#{hero.avatar_id} h3 small", "(20)")
    assert has_element?(view, "#community-avatars-lowest-#{hero.avatar_id}")
    assert has_element?(view, "#community-avatars-lowest-#{unused.id} h3", "0%")
    assert has_element?(view, "#community-arena-stats .community-arena-items #community-balance-items-highest table")
    refute has_element?(view, ".community-balance-result")
    assert has_element?(view, "#community-balance-skills-highest .community-balance-empty")

    view |> element("#pleb-ranking-button") |> render_click()
    assert has_element?(view, "#pleb-ranking-button[aria-pressed=true]")
    assert has_element?(view, "#community-balance-baseline", "50.0%")

    view |> element("#community-admin-toggle") |> render_click()
    refute has_element?(view, "#community-admin-metrics, #community-arena-stats")
    send(view.pid, {"server", %{}})
    assert has_element?(view, "#community-admin-toggle[aria-expanded=false]", "Show stats")
    view |> element("#community-admin-toggle") |> render_click()
    assert has_element?(view, "#community-stat-accounts dd", "2")
  end

  test "admin stats handle zero activity and empty samples", %{conn: conn} do
    hero = create_base_hero()
    user = hero.player.user |> Ecto.Changeset.change(is_admin: true) |> Moba.Repo.update!()
    users = %{new_guests: 0, new_users: 0, online_today: 0, new_heroes: 0}
    balance = %{winrate: 0.0, total: 0, avatars: %{}, skills: %{}, items: %{}}
    cache_admin_stats(%{daily: users, weekly: users}, Map.new(["pvp", "plebs", "elite"], &{&1, balance}))
    conn = conn |> log_in_user(user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")
    assert has_element?(view, "#community-stat-heroes dd", "0")
    assert has_element?(view, "#community-stat-heroes > span", "Training activity")
    assert has_element?(view, "#community-balance-baseline", "0.0%")
    assert has_element?(view, "#community-balance-avatars-lowest .community-balance-empty")
  end

  test "regular players cannot reveal admin stats with forged events", %{conn: conn} do
    hero = create_base_hero()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")
    render_click(view, "toggle-admin")
    render_click(view, "user-filter", %{"period" => "daily"})
    render_click(view, "match-filter", %{"type" => "pvp"})
    refute has_element?(view, "#community-admin-summary, #community-admin-metrics, #community-arena-stats")
  end

  test "recent guests use modern cards inside the admin pulse", %{conn: conn} do
    viewer = create_base_hero()
    user = viewer.player.user |> Ecto.Changeset.change(is_admin: true) |> Moba.Repo.update!()
    guest = Game.create_player!(%{})
    hero = create_base_hero(%{level: 8}, guest) |> Game.buy_item!(base_item())
    guest = Game.get_player!(guest.id)
    users = %{new_guests: 1, new_users: 0, online_today: 1, new_heroes: 1}
    balance = %{winrate: 0.0, total: 0, avatars: %{}, skills: %{}, items: %{}}
    cache_admin_stats(%{daily: users, weekly: users}, Map.new(["pvp", "plebs", "elite"], &{&1, balance}))
    Cachex.put(:game_cache, "match_stats", Map.put(Admin.get_server_data(), :guests, [guest]))
    conn = conn |> log_in_user(user) |> put_session(:player_id, viewer.player_id)
    {:ok, view, _} = live(conn, "/community")

    assert has_element?(view, "#community-admin-summary #community-guests #guest-#{guest.id}.community-guest-card")
    assert has_element?(view, "#guest-#{guest.id} .community-guest-hero strong", hero.avatar.name)
    assert has_element?(view, "#guest-#{guest.id} .community-guest-level", "Lv 8")
    assert has_element?(view, "#guest-#{guest.id} .community-guest-skills img[alt='#{hd(hero.skills).name}']")
    assert has_element?(view, "#guest-#{guest.id} .community-guest-items img[alt='#{base_item().name}']")
    assert has_element?(view, "#guest-#{guest.id} footer", "Joined just now")

    view |> element("#community-admin-toggle") |> render_click()
    refute has_element?(view, "#community-guests")
  end

  test "rankings load only when selected and inactive panels are not rendered", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), pve_ranking: 1})
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")

    assert has_element?(view, "#community-online")
    refute has_element?(view, "#community-pvp")
    refute has_element?(view, "#community-pve")
    assert Cachex.get(:game_cache, "pve_ranking") == {:ok, nil}
    assert Cachex.get(:game_cache, "season_ranking") == {:ok, nil}

    view |> element("#show-pve-link") |> render_click()
    assert has_element?(view, "#community-pve .hero-stats")
    refute has_element?(view, "#community-online")
    refute has_element?(view, "#community-pvp")
    assert {:ok, [_ | _]} = Cachex.get(:game_cache, "pve_ranking")
    assert Cachex.get(:game_cache, "season_ranking") == {:ok, nil}

    view |> element("#show-online-link") |> render_click()
    view |> element("#show-pvp-link") |> render_click()
    assert has_element?(view, "#community-pvp")
    refute has_element?(view, "#community-pve")
    refute has_element?(view, "#community-online")
    assert {:ok, ranking} = Cachex.get(:game_cache, "season_ranking")
    assert is_list(ranking)
  end

  test "renders community and switches ranking tabs", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), pve_ranking: 1})

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, html} = live(conn, "/community")

    assert html =~ "Message Board"

    assert has_element?(
             view,
             "#community-message-form[phx-hook='ResetFormOnEvent'][data-reset-event='community-message-sent']"
           )

    assert html =~ "Updates"
    assert has_element?(view, "#community-message-form")
    assert has_element?(view, "#show-online-link")

    render_click(view, "show-pvp", %{})
    assert has_element?(view, "#show-pvp-link.active")

    render_click(view, "show-pve", %{})
    assert has_element?(view, "#show-pve-link.active")
    assert has_element?(view, ".hero-stats .text-danger[title='Health']")
    assert has_element?(view, ".hero-stats .text-orange[title='Speed']")
    assert has_element?(view, "#skill-#{hero.skills |> List.first() |> Map.fetch!(:id)}-#{hero.id}")
    assert has_element?(view, ".items-container")
  end

  test "creates a community message", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/community")

    html =
      view
      |> form("#community-message-form", %{"message" => %{"body" => "Parity audit message"}})
      |> render_submit()

    assert html =~ "Message Board"

    [message | _] = Accounts.latest_messages("community", "general", 1)
    assert message.body == "Parity audit message"
    assert_push_event(view, "community-message-sent", %{})
    refute_push_event(view, "community-update-sent", %{})
  end

  test "does not clear a rejected message", %{conn: conn} do
    hero = create_base_hero()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")

    view |> form("#community-message-form", %{"message" => %{"body" => "x"}}) |> render_submit()

    refute_push_event(view, "community-message-sent", %{})
  end

  test "clears the admin update title and body only after posting an update", %{conn: conn} do
    hero = create_base_hero()
    user = hero.player.user |> Ecto.Changeset.change(is_admin: true) |> Moba.Repo.update!()
    conn = conn |> log_in_user(user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")

    assert has_element?(
             view,
             "#community-update-form[phx-hook='ResetFormOnEvent'][data-reset-event='community-update-sent']"
           )

    assert has_element?(view, "#community-update-form input[type=text]")
    assert has_element?(view, "#community-update-form textarea")

    view
    |> form("#community-update-form", %{"message" => %{"title" => "New update", "body" => "Development news"}})
    |> render_submit()

    assert_push_event(view, "community-update-sent", %{})
    refute_push_event(view, "community-message-sent", %{})
    [update] = Accounts.latest_messages("community", "updates", 1)
    assert update.title == "New update"
    assert update.body == "Development news"
    assert has_element?(view, "#community-update-#{update.id}", "New update")
  end

  test "preview keeps message and update content, sends messages, and switches tabs", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), pve_ranking: 1})

    attrs = %{
      channel: "community",
      author: hero.player.user.username,
      user_id: hero.player.user_id,
      tier: hero.player.pve_tier
    }

    message =
      Accounts.create_message!(
        Map.merge(attrs, %{topic: "general", body: "A community question\nWith another paragraph"})
      )

    update =
      Accounts.create_message!(
        Map.merge(attrs, %{
          topic: "updates",
          title: "Development news",
          body: "All announcement details remain readable."
        })
      )

    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")

    assert has_element?(view, "#community-message-#{message.id} .inbox-item-text", "A community question")
    assert has_element?(view, "#community-message-#{message.id} .inbox-item-text", "With another paragraph")
    assert has_element?(view, "#community-update-#{update.id}", "Development news")
    assert has_element?(view, "#community-update-#{update.id} .community-update-body", update.body)
    assert has_element?(view, "#community-message-form button[type=submit]")
    assert has_element?(view, "#show-online-link[aria-selected=true]")

    view
    |> form("#community-message-form", %{"message" => %{"body" => "Sent from the new composer"}})
    |> render_submit()

    [sent] = Accounts.latest_messages("community", "general", 1)
    assert sent.body == "Sent from the new composer"
    assert has_element?(view, "#community-message-#{sent.id} .inbox-item-text", sent.body)

    view |> element("#show-pvp-link") |> render_click()
    assert has_element?(view, "#show-pvp-link[aria-selected=true]")
    refute has_element?(view, "#community-pvp.d-none")
    assert has_element?(view, "#show-online-link[aria-selected=false]")

    view |> element("#show-pve-link") |> render_click()
    assert has_element?(view, "#show-pve-link[aria-selected=true]")
    assert has_element?(view, "#community-pve .hero-stats")
    assert has_element?(view, "#community-pve span.game-stat[title^='Total farm:']")
    refute has_element?(view, "#community-pve button, #community-pvp button")
  end

  defp cache_recent_players(ids) do
    players = Admin.current_active_players() |> Enum.filter(&(&1.id in ids))
    Cachex.put(:game_cache, "community_players", players)
  end

  defp cache_admin_stats(user_stats, match_stats) do
    {:ok, previous} = Cachex.get(:game_cache, "match_stats")
    on_exit(fn -> Cachex.put(:game_cache, "match_stats", previous) end)
    data = Admin.get_server_data() |> Map.merge(%{user_stats: user_stats, match_stats: match_stats})
    Cachex.put(:game_cache, "match_stats", data)
  end
end
