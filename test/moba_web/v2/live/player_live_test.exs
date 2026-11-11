defmodule MobaWeb.V2.PlayerLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "connected mount" do
    test "renders player profile from /player/:player_id", %{conn: conn} do
      hero =
        create_base_hero()
        |> Game.buy_item!(base_item())

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/player/#{hero.player_id}")

      assert html =~ hero.player.user.username
      assert has_element?(view, "#user-profile")
      refute has_element?(view, "#profile-cinematic .profile-eyebrow")
      assert has_element?(view, "#profile-ranking-header")
      assert has_element?(view, "#profile-season-ranking-pager[data-initial-row='player-#{hero.player_id}']")
      assert has_element?(view, "#profile-cinematic strong[title='Arena Rating'][data-toggle=tooltip]", "0 AR")
      assert has_element?(view, "#profile-cinematic .profile-metric-label", "Arena Rating")
      assert has_element?(view, "#profile-ranking-header", "Season score")
      assert has_element?(view, "#skill-#{hd(hero.skills).id}-#{hero.id}")
      assert has_element?(view, "#item-#{hd(hero.items).id}-#{hero.id}")
    end

    test "renders player profile from /user/:id", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, _view, html} = live(conn, "/user/#{hero.player.user_id}")

      assert html =~ hero.player.user.username
    end
  end

  test "preview shows registration age first using the largest whole time unit", %{conn: conn} do
    hero = create_base_hero()
    user = hero.player.user
    conn = conn |> log_in_user(user) |> put_session(:player_id, hero.player_id)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    for {shift, expected} <- [
          {[years: -7], "7 years"},
          {[months: -11], "11 months"},
          {[days: -12], "12 days"},
          {[hours: -23], "23 hours"},
          {[minutes: -42], "42 minutes"},
          {[minutes: -1], "1 minute"},
          {[seconds: -10], "0 minutes"}
        ] do
      user
      |> Ecto.Changeset.change(inserted_at: now |> Timex.shift(shift) |> NaiveDateTime.truncate(:second))
      |> Moba.Repo.update!()

      {:ok, view, _} = live(conn, "/player/#{hero.player_id}")
      assert has_element?(view, ".profile-metrics > #profile-registration-age:first-child strong", expected)
      assert has_element?(view, "#profile-registration-age .profile-metric-label", "Registered")
      assert has_element?(view, "#profile-cinematic .profile-cinematic-identity + #profile-actions")
      refute has_element?(view, "#user-profile > .card-footer")
    end
  end

  describe "set-featured event" do
    test "collection includes finished team heroes and orders avatar picks by farm, time, then solo rank", %{conn: conn} do
      player = Game.get_player!(create_player!().id)
      scope = Game.TeamRuns.scope(player)
      run = Test.TeamHelper.team_run(scope, player)
      {:ok, team} = Game.TeamRuns.update(scope, run, &%{&1 | phase: :finished})

      [first, second, third] =
        team.hero_ids
        |> Enum.zip([6_000, 3_000, 3_000])
        |> Enum.map(fn {id, farm} ->
          Game.update_hero!(Game.get_hero!(id), %{total_gold_farm: farm, total_xp_farm: 0})
        end)

      ranked_duplicate =
        create_combat_hero(
          %{finished_at: first.finished_at, pve_ranking: 1, total_gold_farm: 6_000},
          player,
          first.avatar
        )
        |> Ecto.Changeset.change(inserted_at: NaiveDateTime.add(first.inserted_at, -60, :second))
        |> Moba.Repo.update!()

      ranked_tie =
        create_combat_hero(
          %{finished_at: second.finished_at, pve_ranking: 2, total_gold_farm: 3_000},
          player,
          strong_avatar()
        )
        |> Ecto.Changeset.change(inserted_at: second.inserted_at)
        |> Moba.Repo.update!()

      player.id |> Game.get_player!() |> Game.update_collection!([])
      Game.Training.backfill_hero_collections!()

      cached = Enum.find(Game.get_player!(player.id).hero_collection, &(&1["code"] == first.avatar.code))
      assert cached["hero_id"] == ranked_duplicate.id
      assert cached["profile"]["hero_id"] == first.id

      # The profile uses the saved ordering until the next collection refresh.
      Game.update_hero!(third, %{total_gold_farm: 9_000})
      {:ok, view, html} = live(log_in_player(conn, player_id: player.id), "/player/#{player.id}")

      ids =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#profile-collection button[id^=set-featured-]")
        |> LazyHTML.attribute("id")

      assert ids == Enum.map([first, ranked_tie, second, third], &"set-featured-#{&1.id}")
      refute has_element?(view, "#set-featured-#{ranked_duplicate.id}")
      assert has_element?(view, "#set-featured-#{first.id}.current-featured")

      view |> element("#set-featured-#{third.id}") |> render_click()
      assert has_element?(view, "#profile-featured-link[href='/hero/#{third.id}']")
    end

    test "preview selection updates the banner hero and loadout", %{conn: conn} do
      player = Game.get_player!(create_player!().id)

      first =
        create_base_hero(
          %{
            name: player.user.username,
            finished_at: Timex.now(),
            league_tier: Moba.max_league_tier(),
            pve_ranking: 15,
            total_gold_farm: 30_000,
            total_xp_farm: 30_000
          },
          player
        )
        |> Game.buy_item!(base_item())

      Game.update_hero_collection!(first)

      second =
        create_base_hero(
          %{name: "Second hero", finished_at: Timex.now()},
          Game.get_player!(first.player_id),
          strong_avatar()
        )

      Game.update_hero_collection!(second)
      conn = conn |> log_in_user(first.player.user) |> put_session(:player_id, first.player_id)

      {:ok, view, _} = live(conn, "/player/#{first.player_id}")
      view |> element("#set-featured-#{first.id}") |> render_click()
      assert has_element?(view, "#profile-cinematic #hero_#{first.id}")
      assert has_element?(view, "#profile-featured-link[href='/hero/#{first.id}']")
      assert has_element?(view, "#profile-featured-link .profile-featured-title strong", first.name)
      assert has_element?(view, "#profile-featured-link .profile-featured-title .profile-featured-rank", "#15")

      assert has_element?(
               view,
               "#profile-featured-link .profile-featured-level[data-toggle=tooltip]",
               "Level #{first.level} #{first.avatar.name}"
             )

      assert has_element?(view, "#profile-cinematic #item-#{hd(first.items).id}-#{first.id}")
      assert has_element?(view, "#set-featured-#{first.id}[aria-pressed=true][title$='Perfect Run'] .is-undefeated")
      refute has_element?(view, "#set-featured-#{second.id} .is-undefeated")
      refute has_element?(view, "#profile-collection .hero-card")

      view |> element("#set-featured-#{second.id}") |> render_click()
      assert has_element?(view, "#hero_#{second.id} .profile-featured-title strong", "Second hero")
      assert has_element?(view, "#hero_#{second.id} .profile-featured-level", second.avatar.name)
      assert has_element?(view, "#profile-cinematic #skill-#{hd(second.skills).id}-#{second.id}")
      assert has_element?(view, "#set-featured-#{second.id}.current-featured[aria-pressed=true]")
      assert has_element?(view, "#set-featured-#{first.id}[aria-pressed=false] .is-undefeated")
      refute has_element?(view, "#profile-cinematic #hero_#{first.id}")
      refute has_element?(view, "#profile-cinematic #item-#{hd(first.items).id}-#{first.id}")
    end

    test "switches featured hero card", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/player/#{hero.player_id}")
      html = render_click(view, "set-featured", %{"id" => hero.id})
      assert html =~ "hero_#{hero.id}"
    end
  end

  test "profile history switches between 3v3 matches and 1v1 duels with ratings and replays", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_player!()
    season = Game.Duels.create!(hero.player, opponent, true)
    Game.Duels.finish!(season, %{winner: hero.player, attacker_pvp_points: 5, defender_pvp_points: 0})
    live_duel = Game.Duels.create!(opponent, hero.player, false)
    Game.Duels.finish!(live_duel, %{winner: hero.player, attacker_pvp_points: -5, defender_pvp_points: 5})

    match =
      Game.Matches.create!(%{
        player_id: hero.player_id,
        opponent_id: opponent.id,
        winner_id: opponent.id,
        type: "manual",
        phase: "scored",
        rewards: %{attacker_pvp_points: -2}
      })

    {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/player/#{hero.player_id}")

    assert has_element?(view, "#matches-btn[aria-pressed=true]")

    assert has_element?(
             view,
             "#profile-matches-pager[data-page-size='5'] #profile-matches-table tbody[data-listing-rows]"
           )

    assert has_element?(view, "#profile-matches-table .opponent .history-detail", "Manual match")
    assert has_element?(view, "#profile-matches-table [data-result=Defeat] small", "-2 Arena Rating")
    assert has_element?(view, "#profile-matches-table a[href='/matches/#{match.id}'][aria-label]")

    view |> element("#duels-btn") |> render_click()

    assert has_element?(view, "#duels-btn[aria-pressed=true]")
    assert has_element?(view, "#profile-duels-pager[data-page-size='5'] #profile-duels-table tbody[data-listing-rows]")
    refute has_element?(view, "#profile-matches-pager")
    assert has_element?(view, "#profile-duels-table [data-result=Victory] small", "+5 Arena Rating")
    assert has_element?(view, "#profile-duels-table a[href='/arena/#{live_duel.id}'][aria-label]")
    refute has_element?(view, "#profile-arena-debut")
    assert has_element?(view, "#profile-duels-table .opponent a[href='/player/#{opponent.id}']")
    assert has_element?(view, "#profile-duels-table .opponent .history-detail", "Season duel")
    assert has_element?(view, "#profile-duels-table .opponent .history-detail", "Live duel")
    refute has_element?(view, "#profile-duel-record")
    refute render(view) =~ "Normal MM"
  end

  test "another player's 1v1 history has an all-time matchup with the viewer", %{conn: conn} do
    hero = create_base_hero()
    viewer = create_player!()
    duel = Game.Duels.create!(hero.player, viewer, true)
    Game.Duels.finish!(duel, %{winner: nil, attacker_pvp_points: 0, defender_pvp_points: 0})
    Game.update_player!(viewer, %{duel_score: %{"#{hero.player_id}" => 12}})
    Game.update_player!(hero.player, %{duel_score: %{"#{viewer.id}" => 3}})

    {:ok, view, _} = live(log_in_player(conn, player_id: viewer.id), "/player/#{hero.player_id}")
    assert has_element?(view, "#profile-duel-record[aria-label='All-time head-to-head duel record']")
    assert has_element?(view, "#profile-duel-record .profile-duel-player[href='/player/#{viewer.id}']", "You")

    assert has_element?(
             view,
             "#profile-duel-record .profile-duel-opponent[href='/player/#{hero.player_id}']",
             "Opponent"
           )

    assert has_element?(view, "#profile-duel-your-wins[data-leading=true]", "12")
    assert has_element?(view, "#profile-duel-opponent-wins[data-leading=false]", "3")

    view |> element("#matches-btn") |> render_click()
    refute has_element?(view, "#profile-duel-record")
  end

  test "banner shows the viewed player's best hero rank beside season rank and refreshes it", %{conn: conn} do
    viewer = create_base_hero(%{pve_ranking: 1})
    hero = create_base_hero(%{pve_ranking: 405})
    Game.create_hero!(%{name: "Lower placement", pve_ranking: 500}, hero.player, base_avatar(), base_skills())
    {:ok, view, _} = live(log_in_player(conn, player_id: viewer.player_id), "/player/#{hero.player_id}")

    assert has_element?(view, "#profile-season-rank + #profile-team-rank + #profile-hero-rank strong", "405")
    assert has_element?(view, "#profile-hero-rank .profile-metric-label", "Hero rank")

    Game.update_hero!(hero, %{pve_ranking: 300})
    send(view.pid, {"ranking", %{}})
    assert has_element?(view, "#profile-hero-rank strong", "300")
  end

  test "banner shows unranked when the player has no ranked heroes", %{conn: conn} do
    hero = create_base_hero()
    {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/player/#{hero.player_id}")
    assert has_element?(view, "#profile-hero-rank [aria-label=Unranked]", "—")
    assert has_element?(view, "#profile-team-rank [aria-label=Unranked]", "—")
    view |> element("#profile-ranking-team") |> render_click()
    assert has_element?(view, "#profile-no-ranked-teams")
  end

  test "profile shows the viewed player's best team rank and opens the team leaderboard", %{conn: conn} do
    viewer = create_base_hero().player
    owner = create_base_hero().player

    teams =
      for {player, name, farm} <- [
            {owner, "Second team", 30_000},
            {owner, "Best team", 60_000},
            {viewer, "Global leader", 90_000}
          ] do
        scope = Game.TeamRuns.scope(player)
        run = Test.TeamHelper.team_run(scope, player)
        {:ok, finished} = Game.TeamRuns.update(scope, run, &%{&1 | phase: :finished, name: name})
        finished |> Ecto.Changeset.change(total_farm: farm, duration_seconds: 840) |> Moba.Repo.update!()
      end

    [second, best, leader] = teams
    {:ok, view, _} = live(log_in_player(conn, player_id: viewer.id), "/player/#{owner.id}")

    assert has_element?(view, "#profile-team-rank strong", "2")

    assert has_element?(
             view,
             "#profile-ranking-season[aria-pressed=true] + #profile-ranking-team + #profile-ranking-hero"
           )

    view |> element("#profile-ranking-team") |> render_click()
    assert has_element?(view, "#profile-ranking-team[aria-pressed=true]", "Team")
    assert has_element?(view, "#profile-team-ranking-pager[data-initial-row='profile-ranked-team-#{best.id}']")
    assert has_element?(view, "#profile-ranked-team-#{leader.id} td:first-child", "#1")

    assert has_element?(
             view,
             "#profile-ranked-team-#{best.id}.selected-player td:first-child",
             "#2"
           )

    assert has_element?(view, "#profile-ranked-team-#{best.id} a[href='/teams/#{best.id}']", "Best team")
    assert has_element?(view, "#profile-ranked-team-#{best.id} .profile-ranked-team-portraits > img:nth-child(3)")
    assert has_element?(view, "#profile-ranked-team-#{best.id} .profile-training-time h3", "14")
    assert has_element?(view, "#profile-ranked-team-#{second.id}.selected-player td:first-child", "#3")
  end

  describe "season leaderboard" do
    test "identifies each player's arena bracket", %{conn: conn} do
      pleb = create_player!(%{pvp_tier: 0, ranking: 26, season_ranking: 3})
      shadow = create_player!(%{pvp_tier: 1, ranking: 6, season_ranking: 2})
      immortal = create_player!(%{pvp_tier: 2, ranking: 1, season_ranking: 1})
      hero = create_base_hero(%{}, pleb)
      ranking = Enum.map([immortal, shadow, pleb], &Game.get_player!(&1.id))
      Cachex.put(:game_cache, "season_ranking", ranking)
      on_exit(fn -> Cachex.del(:game_cache, "season_ranking") end)
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, pleb.id)
      {:ok, view, _} = live(conn, "/player/#{hero.player_id}")

      for {player, bracket} <- [{pleb, "Plebs"}, {shadow, "Shadows"}, {immortal, "Immortals"}] do
        assert has_element?(view, "#player-#{player.id}[data-bracket='#{bracket}'] .profile-ranking-bracket", bracket)
      end

      assert has_element?(view, "#player-#{pleb.id}.selected-player")
    end

    test "defaults to season rank without a top-200 hero and keeps season updates working", %{conn: conn} do
      player =
        create_player!(%{
          ranking: 26,
          season_ranking: 3,
          pve_tier: 1,
          best_immortal_streak: 3,
          pvp_points: 25,
          daily_wins: 9
        })

      hero = create_base_hero(%{}, player)
      daily_player = create_player!(%{ranking: 1, daily_wins: 30})
      Cachex.put(:game_cache, "season_ranking", [Game.get_player!(player.id)])
      Cachex.put(:game_cache, "daily_ranking", [daily_player])

      on_exit(fn ->
        Cachex.del(:game_cache, "season_ranking")
        Cachex.del(:game_cache, "daily_ranking")
      end)

      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, player.id)
      {:ok, view, _} = live(conn, "/player/#{player.id}")
      assert has_element?(view, "#profile-ranking-header", "Season score")
      assert has_element?(view, "#player-#{player.id} h1", "#3")
      assert has_element?(view, "#season-player-#{player.id}", "185")
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]", "Season")
      assert has_element?(view, "#profile-ranking-hero", "Hero")
      refute has_element?(view, "#profile-hero-ranking-table, #daily-player-#{player.id}")
      refute has_element?(view, "#player-#{daily_player.id}")

      updated = Game.update_player!(Game.get_player!(player.id), %{pvp_points: 35})
      Cachex.put(:game_cache, "season_ranking", [updated])
      send(view.pid, {"ranking", %{}})
      assert has_element?(view, "#season-player-#{player.id}", "195")
      assert has_element?(view, "#profile-ranking-header", "Season score")
    end

    test "the player's footer keeps a three-digit rank, identity, and score in separate columns", %{conn: conn} do
      player =
        create_player!(%{
          ranking: 26,
          season_ranking: 849,
          pve_tier: 1,
          best_immortal_streak: 3,
          pvp_points: 25,
          daily_wins: 9
        })

      hero = create_base_hero(%{}, player)
      Cachex.put(:game_cache, "season_ranking", [])
      on_exit(fn -> Cachex.del(:game_cache, "season_ranking") end)
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, player.id)
      {:ok, view, _} = live(conn, "/player/#{player.id}")
      assert has_element?(view, "#profile-current-standing.selected-player > th:first-child h1", "#849")

      assert has_element?(
               view,
               "#profile-current-standing > th:nth-child(2) .profile-ranked-identity[href='/player/#{player.id}'] .profile-ranked-avatar"
             )

      assert has_element?(
               view,
               "#profile-current-standing > th:nth-child(2) .profile-ranked-name",
               hero.player.user.username
             )

      assert has_element?(view, "#profile-ranking-table tfoot h3", "185")
    end
  end

  describe "hero leaderboard" do
    setup do
      Cachex.put(:game_cache, "pve_ranking", [])
      on_exit(fn -> Cachex.del(:game_cache, "pve_ranking") end)
      :ok
    end

    test "season rank remains the default even with a top-200 hero, and Hero Rank highlights its placement", %{
      conn: conn
    } do
      hero = create_base_hero()
      hero = Game.update_hero!(hero, %{pve_ranking: 200, finished_at: Timex.shift(hero.inserted_at, minutes: 12)})

      outside =
        Game.create_hero!(%{name: "Outside top 200"}, hero.player, base_avatar(), base_skills())
        |> Game.update_hero!(%{pve_ranking: 201})

      leader = create_base_hero() |> Game.update_hero!(%{pve_ranking: 1})
      Cachex.put(:game_cache, "pve_ranking", Enum.map([outside, hero, leader], &Game.get_hero!(&1.id)))
      {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/player/#{hero.player_id}")

      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]", "Season")
      view |> element("#profile-ranking-hero") |> render_click()
      assert has_element?(view, "#profile-ranking-hero[aria-pressed=true]", "Hero")

      assert has_element?(
               view,
               "#profile-ranked-hero-#{hero.id}.selected-player .profile-hero-position",
               "#200"
             )

      assert has_element?(view, "#profile-ranked-hero-#{hero.id} a[href='/hero/#{hero.id}']")
      assert has_element?(view, "#profile-ranked-hero-#{hero.id} .profile-training-time h3", "12")
      refute has_element?(view, "#profile-ranked-hero-#{outside.id}, #profile-ranking-table")

      view |> element("#profile-ranking-season") |> render_click()
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")
      assert has_element?(view, "#profile-ranking-table")
      refute has_element?(view, "#profile-hero-ranking-table")
      send(view.pid, {"ranking", %{}})
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")

      view |> element("#profile-ranking-hero") |> render_click()
      assert has_element?(view, "#profile-hero-ranking-table")
      assert has_element?(view, "#profile-hero-ranking-pager[data-initial-row='profile-ranked-hero-#{hero.id}']")
    end

    test "only a top-200 hero qualifies and the empty hero leaderboard stays usable", %{conn: conn} do
      hero = create_base_hero() |> Game.update_hero!(%{pve_ranking: 201})
      Cachex.put(:game_cache, "pve_ranking", [Game.get_hero!(hero.id)])
      {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/player/#{hero.player_id}")
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")
      view |> element("#profile-ranking-hero") |> render_click()
      assert has_element?(view, "#profile-no-ranked-heroes")
      refute has_element?(view, "#profile-ranked-hero-#{hero.id}")
    end

    test "another profile's heroes are highlighted and its best hero sets the starting page",
         %{conn: conn} do
      viewer = create_base_hero() |> Game.update_hero!(%{pve_ranking: 1})
      profile_hero = create_base_hero() |> Game.update_hero!(%{pve_ranking: 50})

      second =
        Game.create_hero!(%{name: "Second ranked hero"}, profile_hero.player, base_avatar(), base_skills())
        |> Game.update_hero!(%{pve_ranking: 100})

      Cachex.put(:game_cache, "pve_ranking", Enum.map([viewer, profile_hero, second], &Game.get_hero!(&1.id)))
      {:ok, view, _} = live(log_in_player(conn, player_id: viewer.player_id), "/player/#{profile_hero.player_id}")
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")
      view |> element("#profile-ranking-hero") |> render_click()
      assert has_element?(view, "#profile-ranking-hero[aria-pressed=true]")

      assert has_element?(
               view,
               "#profile-hero-ranking-pager[data-initial-row='profile-ranked-hero-#{profile_hero.id}']"
             )

      assert has_element?(view, "#profile-ranked-hero-#{profile_hero.id}.selected-player")
      assert has_element?(view, "#profile-ranked-hero-#{second.id}.selected-player")
      refute has_element?(view, "#profile-ranked-hero-#{viewer.id}.selected-player")

      updated = Game.update_hero!(profile_hero, %{finished_at: Timex.shift(profile_hero.inserted_at, minutes: 24)})
      Cachex.put(:game_cache, "pve_ranking", Enum.map([viewer, updated, second], &Game.get_hero!(&1.id)))
      send(view.pid, {"ranking", %{}})
      assert has_element?(view, "#profile-ranked-hero-#{profile_hero.id} .profile-training-time h3", "24")
      assert has_element?(view, "#profile-ranking-hero[aria-pressed=true]")
    end
  end
end
