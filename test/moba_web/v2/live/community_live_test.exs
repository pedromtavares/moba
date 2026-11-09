defmodule MobaWeb.V2.CommunityLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    for key <- ["pve_ranking", "season_ranking", "community_players", "community_guests"],
        do: Cachex.del(:game_cache, key)

    on_exit(fn ->
      for key <- ["pve_ranking", "season_ranking", "community_players", "community_guests"],
          do: Cachex.del(:game_cache, key)
    end)

    :ok
  end

  test "Top Teams sits between the rankings and links to finished training teams", %{conn: conn} do
    owner = create_base_hero().player
    scope = Game.TeamRuns.scope(owner)
    run = Test.TeamHelper.team_run(scope, owner)
    {:ok, finished} = Game.TeamRuns.update(scope, run, &%{&1 | phase: :finished, name: "Moonwatch"})
    unfinished = Test.TeamHelper.team_run(scope, owner)
    Accounts.set_online_now(owner.user)
    cache_recent_players([owner.id])

    viewer = create_base_hero().player
    {:ok, view, _} = live(log_in_player(conn, player_id: viewer.id), "/community")

    assert has_element?(view, "#user-#{owner.id} .community-best-team-rank[href='/teams/#{finished.id}']", "#1")
    assert has_element?(view, "#show-pvp-link + #show-teams-link + #show-pve-link")
    assert has_element?(view, "#show-teams-link img.nav-emblem[src='/images/navigation/base.webp']")
    view |> element("#show-teams-link") |> render_click()

    card = "#community-teams #community-team-#{finished.id}"
    assert has_element?(view, "#{card}[href='/teams/#{finished.id}']", "Moonwatch")
    assert has_element?(view, "#{card} header .community-player-rank", "#1")
    assert has_element?(view, "#{card} .community-ranking-footer dt", "Avg farm")
    assert has_element?(view, "#{card} .community-ranking-footer dt", "Time")
    assert has_element?(view, "#{card} .community-team-portraits > div:nth-child(3) span")
    refute has_element?(view, "#community-team-#{unfinished.id}")
  end

  test "recent players show the latest training roster or solo hero with a compact activity footer", %{conn: conn} do
    owner = create_base_hero().player
    scope = Game.TeamRuns.scope(owner)
    run = Test.TeamHelper.team_run(scope, owner)
    {:ok, run} = Game.TeamRuns.update(scope, run, &Map.put(&1, :name, "Moonwatch"))
    Accounts.set_online_now(owner.user)
    cache_recent_players([owner.id])

    viewer = create_base_hero().player
    {:ok, view, _} = live(log_in_player(conn, player_id: viewer.id), "/community")
    card = "#user-#{owner.id}"

    assert has_element?(view, "#{card}.community-recent-team-card")

    for {%{hero: hero}, position} <- Enum.with_index(Game.TeamTraining.team(Game.TeamRuns.state(run)), 1) do
      portrait = "#{card} .community-team-portraits > div:nth-child(#{position})"
      assert has_element?(view, ~s(#{portrait}[role=img][aria-label="#{hero.avatar.name}"][style*="--team-hero-art"]))
      refute has_element?(view, "#{portrait} span")
    end

    assert has_element?(view, "#{card} .community-activity-metrics dt", "Started training")
    assert has_element?(view, "#{card} .community-activity-metrics dd", "Moonwatch")
    assert has_element?(view, "#{card} .community-activity-metrics time[datetime]")
    refute has_element?(view, "#{card} a.community-activity-link")

    {:ok, finished} = Game.TeamRuns.update(scope, run, &%{&1 | phase: :finished})
    cache_recent_players([owner.id])
    send(view.pid, :refresh_recent_players)
    assert has_element?(view, "#{card} .community-activity-link[href='/teams/#{finished.id}']", "Finished training")
    assert has_element?(view, "#{card} .community-team-portraits > div:nth-child(3)")

    solo =
      Game.create_hero!(%{name: "New solo"}, owner, base_avatar(), base_skills())
      |> Ecto.Changeset.change(
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.add(1)
      )
      |> Moba.Repo.update!()

    cache_recent_players([owner.id])
    send(view.pid, :refresh_recent_players)
    refute has_element?(view, "#{card} .community-team-portraits")
    assert has_element?(view, "#{card}[style*='--player-art']")
    assert has_element?(view, "#{card} .community-activity-link[href='/hero/#{solo.id}']", "Started training")
  end

  test "top player cards show direct score contributions, Arena titles and prominent footer metrics", %{conn: conn} do
    entries =
      for {tier, rank} <- [{2, 1}, {2, 2}, {1, 6}, {0, 26}] do
        player =
          create_player!(%{
            pve_tier: 7,
            pvp_tier: tier,
            ranking: rank,
            best_immortal_streak: 3,
            pvp_points: 120,
            total_matches: 10,
            total_wins: 8,
            season_ranking: rank
          })

        hero =
          Game.create_hero!(
            %{name: "Featured", finished_at: Timex.now(), league_tier: 6},
            player,
            base_avatar(),
            base_skills()
          )

        player = Game.get_player!(player.id)
        Map.put(player, :top_hero, hero)
      end

    [holder, immortal, shadow, pleb] = entries

    for _ <- 1..3 do
      Game.Matches.create!(%{player_id: holder.id, opponent_id: pleb.id, winner_id: holder.id, phase: "scored"})
    end

    Game.Matches.create!(%{player_id: holder.id, opponent_id: pleb.id, winner_id: pleb.id, phase: "scored"})
    Cachex.put(:game_cache, "season_ranking", entries)
    {:ok, view, _} = live(log_in_player(conn, player_id: holder.id), "/community")
    view |> element("#show-pvp-link") |> render_click()

    for {player, title} <- [{holder, "The Immortal"}, {immortal, "Immortals"}, {shadow, "Shadow"}] do
      assert has_element?(view, "#player-card-#{player.id} .player-card-arena-title", title)
    end

    refute has_element?(view, "#player-card-#{pleb.id} .player-card-arena-title")
    assert has_element?(view, "#player-season-score-#{holder.id}", "1080")

    assert has_element?(
             view,
             "#player-card-#{holder.id} .community-ranking-footer [data-metric=arena-rating] dd",
             "120"
           )

    assert has_element?(view, "#player-card-#{holder.id} [data-metric=win-rate] dd", "75%")
    assert has_element?(view, "#player-card-#{holder.id} [data-metric=immortal-streak] dd", "3")

    tooltip =
      view
      |> element("#player-season-score-#{holder.id}")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("title")
      |> hd()
      |> LazyHTML.from_fragment()

    assert LazyHTML.query(tooltip, ".skill-tooltip.season-score-tooltip") |> Enum.count() == 1
    assert LazyHTML.query(tooltip, "[data-score-source=training] dt") |> LazyHTML.text() |> String.trim() == "Invoker"
    assert LazyHTML.query(tooltip, "[data-score-source=training] dd") |> LazyHTML.text() == "700"
    assert LazyHTML.query(tooltip, "[data-score-source=streak] dd") |> LazyHTML.text() == "60"
    assert LazyHTML.query(tooltip, "[data-score-source=immortal] dd") |> LazyHTML.text() == "+200"

    changed =
      Enum.map(entries, fn player ->
        cond do
          player.id == holder.id -> %{player | ranking: 2}
          player.id == immortal.id -> %{player | ranking: 1}
          true -> player
        end
      end)

    Cachex.put(:game_cache, "season_ranking", changed)
    send(view.pid, {"ranking", %{}})
    assert has_element?(view, "#player-card-#{immortal.id} .player-card-arena-title", "The Immortal")
    assert has_element?(view, "#player-season-score-#{holder.id}", "880")
  end

  test "recent player cards show activity and ranks with no recent hero strip", %{conn: conn} do
    hero = create_base_hero(%{pve_ranking: 15})
    player = Game.update_player!(hero.player, %{season_ranking: 3})
    opponent = create_player!()

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

    assert has_element?(view, "#community-recent-players > article[data-community-entry]")
    refute has_element?(view, "#community-recent-players .community-recent-hero, #community-recent-players table")
    assert has_element?(view, "#user-#{player.id}[data-current=true] .community-player-identity", player.user.username)
    assert has_element?(view, "#user-#{player.id} .community-player-status", "Online")
    assert has_element?(view, "#user-#{player.id} .community-season-rank", "#3")
    assert has_element?(view, "#user-#{player.id} .community-best-hero-rank[href='/hero/#{hero.id}']", "#15")

    assert has_element?(
             view,
             "#user-#{player.id} > footer.community-ranking-footer .community-activity-link[href='/matches/#{match.id}']",
             "Won a 3v3"
           )

    assert has_element?(
             view,
             "#user-#{player.id} .community-activity-link small",
             Accounts.get_user!(opponent.user_id).username
           )
  end

  test "presence labels and dots follow the two-hour and one-day boundaries", %{conn: conn} do
    viewer = create_base_hero()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    players =
      for {seconds, recency} <- [
            {0, "recent"},
            {7_140, "recent"},
            {7_200, "away"},
            {86_340, "away"},
            {86_400, "offline"},
            {172_800, "offline"}
          ] do
        user =
          create_user() |> Ecto.Changeset.change(last_online_at: DateTime.add(now, -seconds)) |> Moba.Repo.update!()

        {create_player!(%{}, user), recency}
      end

    cache_recent_players(Enum.map(players, fn {player, _} -> player.id end))
    {:ok, view, _} = live(log_in_player(conn, player_id: viewer.player_id), "/community")

    for {player, recency} <- players do
      assert has_element?(
               view,
               "#user-#{player.id} .community-player-status[data-activity=#{recency}]",
               %{"recent" => "Online", "away" => "Away", "offline" => "Offline"}[recency]
             )
    end

    assert has_element?(view, ".community-player-status .community-status-dot[aria-hidden=true]")
    refute has_element?(view, ".community-player-status[title], .community-player-status[datetime]")

    {player, _} = hd(players)

    Accounts.get_user!(player.user_id)
    |> Ecto.Changeset.change(last_online_at: DateTime.add(now, -86_400))
    |> Moba.Repo.update!()

    Cachex.del(:game_cache, "community_players")
    send(view.pid, :refresh_recent_players)

    assert has_element?(
             view,
             "#user-#{player.id} .community-player-status[data-activity=offline]",
             "Offline"
           )
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
    refute has_element?(view, "#user-#{offline_player.id} > footer")

    live_player = Game.set_player_unavailable!(live_player)
    refute has_element?(view, "#user-#{live_player.id} .community-player-live")
    Game.set_player_available!(live_player)
    assert has_element?(view, "#user-#{live_player.id} .community-player-live")
  end

  test "only admins receive player activity timestamp tooltips", %{conn: conn} do
    hero = create_base_hero()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    active_at = DateTime.add(now, -3_600)
    registered_at = now |> DateTime.add(-7 * 86_400) |> DateTime.to_naive()

    user =
      hero.player.user
      |> Ecto.Changeset.change(last_online_at: active_at, inserted_at: registered_at)
      |> Moba.Repo.update!()

    cache_recent_players([hero.player_id])
    viewer = create_base_hero()
    viewer_conn = conn |> log_in_user(viewer.player.user) |> put_session(:player_id, viewer.player_id)
    {:ok, view, _} = live(viewer_conn, "/community")

    refute has_element?(view, "#user-#{hero.player_id} .community-player-status[data-toggle=tooltip]")
    refute has_element?(view, "#user-#{hero.player_id} .community-player-status[title]")

    admin = viewer.player.user |> Ecto.Changeset.change(is_admin: true) |> Moba.Repo.update!()
    admin_conn = conn |> log_in_user(admin) |> put_session(:player_id, viewer.player_id)
    {:ok, view, _} = live(admin_conn, "/community")

    assert has_element?(
             view,
             "#user-#{hero.player_id} .community-player-status[data-toggle=tooltip][tabindex='0'][title='Last active: 1h ago<br/>Registered: 7 days ago']"
           )

    {:ok, players} = Cachex.get(:game_cache, "community_players")
    Cachex.put(:game_cache, "community_players", Enum.map(players, &%{&1 | user: %{user | last_online_at: nil}}))
    send(view.pid, :refresh_recent_players)

    assert has_element?(
             view,
             "#user-#{hero.player_id} .community-player-status[data-activity=offline][title*='Last active: time unavailable']",
             "Offline"
           )
  end

  test "admin registration tooltips express older accounts in readable months and years", %{conn: conn} do
    hero = create_base_hero()
    Accounts.set_online_now(hero.player.user)
    viewer = create_base_hero()
    admin = viewer.player.user |> Ecto.Changeset.change(is_admin: true) |> Moba.Repo.update!()
    conn = conn |> log_in_user(admin) |> put_session(:player_id, viewer.player_id)
    cache_recent_players([hero.player_id])
    {:ok, view, _} = live(conn, "/community")

    for {days, expected} <- [{40, "1 month ago"}, {90, "3 months ago"}, {400, "1 year ago"}, {700, "2 years ago"}] do
      registered_at =
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-days * 86_400) |> DateTime.to_naive()

      hero.player.user |> Ecto.Changeset.change(inserted_at: registered_at) |> Moba.Repo.update!()
      cache_recent_players([hero.player_id])
      send(view.pid, :refresh_recent_players)

      assert has_element?(
               view,
               "#user-#{hero.player_id} .community-player-status[title*='Registered: #{expected}']"
             )
    end
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

  test "admin metrics appear in Recent Players and Arena Stats keeps the original table information", %{conn: conn} do
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

    assert has_element?(view, "#community-period-weekly[aria-pressed=true]", "Weekly")
    assert has_element?(view, "#community-stat-accounts dd", "8")
    assert has_element?(view, "#show-online-link[aria-selected=true]")
    assert has_element?(view, "#community-online #community-admin-metrics > div:nth-child(3)")
    refute has_element?(view, "#show-pulse-link, #community-admin-metrics > div:nth-child(4)")
    refute has_element?(view, "#community-arena-stats, #community-duel-history")
    view |> element("#community-period-daily") |> render_click()
    assert has_element?(view, "#community-period-daily[aria-pressed=true]")
    assert has_element?(view, "#community-stat-accounts dd", "2")
    assert has_element?(view, "#community-stat-guests dd", "4")
    assert has_element?(view, "#community-stat-active dd", "5")

    view |> element("#show-balance-link") |> render_click()
    refute has_element?(view, "#community-online")
    assert has_element?(view, "#community-balance-baseline", "55.0%")
    assert has_element?(view, "#community-arena-stats-title", "Arena Stats")
    assert has_element?(view, "#community-avatars-highest-#{hero.avatar_id} h3.text-warning", "60%")
    assert has_element?(view, "#community-avatars-highest-#{hero.avatar_id} h3 small", "(20)")
    assert has_element?(view, "#community-avatars-lowest-#{hero.avatar_id}")
    assert has_element?(view, "#community-avatars-lowest-#{unused.id} h3", "0%")
    view |> element("#community-balance-category-items") |> render_click()
    assert has_element?(view, "#community-balance-items-highest .community-balance-empty")
    view |> element("#community-balance-category-skills") |> render_click()
    assert has_element?(view, "#community-balance-skills-highest .community-balance-empty")

    view |> element("#pleb-ranking-button") |> render_click()
    assert has_element?(view, "#pleb-ranking-button[aria-pressed=true]")
    assert has_element?(view, "#community-balance-baseline", "50.0%")

    view |> element("#show-online-link") |> render_click()
    refute has_element?(view, "#community-arena-stats")
    send(view.pid, {"server", %{}})
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
    assert has_element?(view, "#community-stat-guests dd", "0")
    view |> element("#show-balance-link") |> render_click()
    assert has_element?(view, "#community-balance-baseline", "0.0%")
    assert has_element?(view, "#community-balance-avatars-lowest .community-balance-empty")
  end

  test "regular players cannot reveal admin stats with forged events", %{conn: conn} do
    hero = create_base_hero()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")
    render_click(view, "show-balance")
    render_click(view, "show-pulse")
    render_click(view, "user-filter", %{"period" => "daily"})
    render_click(view, "match-filter", %{"type" => "pvp"})

    refute has_element?(
             view,
             "#community-pulse, #show-pulse-link, #community-admin-summary, #community-arena-stats, #show-balance-link"
           )
  end

  test "guests can browse Recent Players and see their own card after registered players", %{conn: conn} do
    viewer = create_base_hero()
    Accounts.set_online_now(viewer.player.user)

    guest = Game.create_player!(%{})
    hero = create_base_hero(%{level: 8, league_tier: 1}, guest) |> Game.buy_item!(base_item())
    joined_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.add(-7_200)

    Game.get_player!(guest.id)
    |> Ecto.Changeset.change(inserted_at: joined_at, updated_at: joined_at)
    |> Moba.Repo.update!()

    roster_guest =
      Game.create_player!(%{})
      |> Ecto.Changeset.change(inserted_at: joined_at, updated_at: joined_at, pve_tier: 1)
      |> Moba.Repo.update!()

    scope = %{user: nil, player_id: roster_guest.id}
    record = Test.TeamHelper.team_run(scope, roster_guest)

    {:ok, record} =
      Game.TeamRuns.update(scope, record, fn run ->
        run
        |> Map.put(:league_tier, 3)
        |> put_in([:heroes, 1, :hero, Access.key(:level)], 3)
        |> put_in([:heroes, 2, :hero, Access.key(:level)], 6)
        |> put_in([:heroes, 3, :hero, Access.key(:level)], 9)
      end)

    draft_guest = Game.TeamRuns.start_guest!(Ecto.UUID.generate(), hd(Test.TeamHelper.team_picks(scope)))

    assert is_nil(Game.get_player!(roster_guest.id).current_pve_hero_id)

    guest_conn = log_in_player(conn, player_id: roster_guest.id)
    {:ok, view, html} = live(guest_conn, "/community")

    refute html =~ ~s(href="/community")
    assert has_element?(view, "#community-recent-players > #user-#{viewer.player_id} + #guest-#{roster_guest.id}")
    assert has_element?(view, "#guest-#{roster_guest.id}[data-current=true] .community-player-name", "You")
    assert has_element?(view, "#guest-#{guest.id}.community-player-card .community-player-name", "Guest ##{guest.id}")
    assert has_element?(view, "#guest-#{guest.id} .community-guest-solo-caption", hero.avatar.name)
    assert has_element?(view, "#guest-#{guest.id} .community-guest-solo-caption .community-guest-level", "Lv 8")
    solo_footer = "#guest-#{guest.id} > footer.community-ranking-footer"
    roster_footer = "#guest-#{roster_guest.id} > footer.community-ranking-footer"
    assert has_element?(view, "#{solo_footer} .community-activity-time dt", "Joined")
    assert has_element?(view, "#{solo_footer} .community-activity-metrics time[datetime]", "2h ago")
    assert has_element?(view, "#{solo_footer} [data-toggle=tooltip][title='PvE rank: Initiate']")
    assert has_element?(view, "#{solo_footer} .community-activity-metrics dt", "Silver League")
    assert has_element?(view, "#{roster_footer} [data-toggle=tooltip][title='PvE rank: Novice']")
    assert has_element?(view, "#{roster_footer} .community-activity-metrics dt", "Platinum League")
    refute has_element?(view, "#community-admin-summary")

    for {%{hero: member}, index} <-
          record |> Game.TeamRuns.state() |> Game.TeamTraining.team() |> Enum.with_index(1) do
      portrait = "#guest-#{roster_guest.id} .community-team-portraits > div:nth-child(#{index})"
      label = "#{member.avatar.name}, level #{member.level}"
      assert has_element?(view, ~s(#{portrait}[role=img][aria-label="#{label}"][style*="--team-hero-art"]))
      assert has_element?(view, "#{portrait} .community-guest-level", "Lv #{member.level}")
      refute has_element?(view, "#{portrait} span", member.avatar.name)
    end

    assert has_element?(view, "#guest-#{draft_guest.id} .community-guest-level", "Lv 1")
    assert has_element?(view, "#guest-#{draft_guest.id} .community-activity-metrics dt", "Bronze League")

    view |> element("#show-pvp-link") |> render_click()
    refute has_element?(view, "#guest-#{guest.id}")
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
    assert has_element?(view, "#community-pve #community-hero-#{hero.id}")
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

  test "top hero cards show rank, combat stats and the current loadout tooltips", %{conn: conn} do
    item = base_item()

    hero =
      create_base_hero(%{pve_ranking: 1, total_gold_farm: 30_000, total_xp_farm: 30_000})
      |> Game.buy_item!(item)
      |> Game.update_hero!(%{finished_at: Timex.now()})

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _} = live(conn, "/community")

    refute has_element?(
             view,
             "#community-board, #community-announcements, #community-message-form, #community-update-form"
           )

    assert has_element?(view, "#community-recent-players-pages[phx-hook=CommunityPager]")
    assert has_element?(view, "#show-online-link")

    render_click(view, "show-pvp", %{})
    assert has_element?(view, "#show-pvp-link.active")

    render_click(view, "show-pve", %{})
    assert has_element?(view, "#show-pve-link.active")

    card = "#community-hero-#{hero.id}"
    assert has_element?(view, "#{card} .community-player-name[href='/hero/#{hero.id}']", hero.name)
    assert has_element?(view, "#{card} .community-player-heading > .community-player-rank", "#1")
    assert has_element?(view, "#{card} .community-hero-meta > .community-hero-avatar", hero.avatar.name)
    assert has_element?(view, "#{card} .community-hero-meta > .community-hero-level", "Level #{hero.level}")
    assert has_element?(view, "#{card} .community-hero-metrics dd", "60K")

    document = view |> element(card) |> render() |> LazyHTML.from_fragment()
    [stats] = document |> LazyHTML.query(".community-hero-level") |> LazyHTML.attribute("title")
    stats = LazyHTML.from_fragment(stats)
    assert LazyHTML.text(LazyHTML.query(stats, "[data-stat=hp] span")) == "Health"
    assert LazyHTML.text(LazyHTML.query(stats, "[data-stat=speed] span")) == "Speed"

    for {resource, kind, selector} <- [
          {List.first(hero.skills), "skill", ".skill-tooltip"},
          {item, "item", ".item-tooltip"}
        ] do
      image = LazyHTML.query(document, "img##{kind}-#{resource.id}-#{hero.id}[data-toggle=tooltip]")
      assert LazyHTML.attribute(image, "src") == [MobaWeb.V2.Components.GameHelpers.image_url(resource)]
      [tooltip] = LazyHTML.attribute(image, "title")
      assert tooltip |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.text() =~ resource.name
    end
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
