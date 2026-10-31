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
      assert has_element?(view, "#profile-ranking-header")
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
      assert has_element?(view, "#user-profile > .card-footer #profile-actions")
      refute has_element?(view, "#user-profile > .card-footer .font-italic")
    end
  end

  describe "set-featured event" do
    test "preview selection updates the banner hero and loadout", %{conn: conn} do
      first = create_base_hero(%{finished_at: Timex.now()}) |> Game.buy_item!(base_item())
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
      assert has_element?(view, "#profile-cinematic #item-#{hd(first.items).id}-#{first.id}")
      refute has_element?(view, "#profile-collection .hero-card")

      view |> element("#set-featured-#{second.id}") |> render_click()
      assert has_element?(view, "#profile-cinematic #hero_#{second.id}", "Second hero")
      assert has_element?(view, "#profile-cinematic #skill-#{hd(second.skills).id}-#{second.id}")
      assert has_element?(view, "#set-featured-#{second.id}.current-featured")
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

  test "1v1 history identifies season and live duels beneath the opponent name", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_player!()
    season = Game.Duels.create!(hero.player, opponent, true)
    Game.Duels.finish!(season, %{winner: hero.player, attacker_pvp_points: 5, defender_pvp_points: 0})
    live_duel = Game.Duels.create!(opponent, hero.player, false)
    Game.Duels.finish!(live_duel, %{winner: hero.player, attacker_pvp_points: -5, defender_pvp_points: 5})
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/player/#{hero.player_id}")

    assert has_element?(view, "#matches-btn")
    refute has_element?(view, "#profile-arena-debut")
    assert has_element?(view, "#profile-duels-table .opponent a[href='/player/#{opponent.id}']")
    assert has_element?(view, "#profile-duels-table .opponent .history-detail", "Season duel")
    assert has_element?(view, "#profile-duels-table .opponent .history-detail", "Live duel")
    refute render(view) =~ "Normal MM"
  end

  test "banner shows the viewed player's best hero rank beside season rank and refreshes it", %{conn: conn} do
    viewer = create_base_hero(%{pve_ranking: 1})
    hero = create_base_hero(%{pve_ranking: 405})
    Game.create_hero!(%{name: "Lower placement", pve_ranking: 500}, hero.player, base_avatar(), base_skills())
    {:ok, view, _} = live(init_test_session(conn, player_id: viewer.player_id), "/player/#{hero.player_id}")

    assert has_element?(view, "#profile-season-rank + #profile-hero-rank strong", "405")
    assert has_element?(view, "#profile-hero-rank .profile-metric-label", "Hero rank")

    Game.update_hero!(hero, %{pve_ranking: 300})
    send(view.pid, {"ranking", %{}})
    assert has_element?(view, "#profile-hero-rank strong", "300")
  end

  test "banner shows unranked when the player has no ranked heroes", %{conn: conn} do
    hero = create_base_hero()
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/player/#{hero.player_id}")
    assert has_element?(view, "#profile-hero-rank [aria-label=Unranked]", "—")
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
      assert has_element?(view, "#season-player-#{player.id}", "425")
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]", "Season Rank")
      assert has_element?(view, "#profile-ranking-hero", "Hero Rank")
      refute has_element?(view, "#profile-hero-ranking-table, #daily-player-#{player.id}")
      refute has_element?(view, "#player-#{daily_player.id}")

      updated = Game.update_player!(Game.get_player!(player.id), %{pvp_points: 35})
      Cachex.put(:game_cache, "season_ranking", [updated])
      send(view.pid, {"ranking", %{}})
      assert has_element?(view, "#season-player-#{player.id}", "435")
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
      assert has_element?(view, "#profile-current-standing > th:nth-child(2) .profile-ranked-identity[href='/player/#{player.id}'] .profile-ranked-avatar")
      assert has_element?(view, "#profile-current-standing > th:nth-child(2) .profile-ranked-name", hero.player.user.username)
      assert has_element?(view, "#profile-ranking-table tfoot h3", "425")
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
      hero = create_base_hero() |> Game.update_hero!(%{pve_ranking: 200, total_gold_farm: 100, total_xp_farm: 200})

      outside =
        Game.create_hero!(%{name: "Outside top 200"}, hero.player, base_avatar(), base_skills())
        |> Game.update_hero!(%{pve_ranking: 201})

      leader = create_base_hero() |> Game.update_hero!(%{pve_ranking: 1})
      Cachex.put(:game_cache, "pve_ranking", Enum.map([outside, hero, leader], &Game.get_hero!(&1.id)))
      {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/player/#{hero.player_id}")

      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]", "Season Rank")
      view |> element("#profile-ranking-hero") |> render_click()
      assert has_element?(view, "#profile-ranking-hero[aria-pressed=true]", "Hero Rank")

      assert has_element?(
               view,
               "#profile-ranked-hero-#{hero.id}.selected-player[phx-hook=HalfScroll] .profile-hero-position",
               "#200"
             )

      assert has_element?(view, "#profile-ranked-hero-#{hero.id} a[href='/hero/#{hero.id}']")
      assert has_element?(view, "#profile-ranked-hero-#{hero.id} .profile-hero-farm", "300")
      refute has_element?(view, "#profile-ranked-hero-#{outside.id}, #profile-ranking-table")

      view |> element("#profile-ranking-season") |> render_click()
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")
      assert has_element?(view, "#profile-ranking-table")
      refute has_element?(view, "#profile-hero-ranking-table")
      send(view.pid, {"ranking", %{}})
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")

      view |> element("#profile-ranking-hero") |> render_click()
      assert has_element?(view, "#profile-hero-ranking-table")
      assert has_element?(view, "#profile-ranked-hero-#{hero.id}[phx-hook=HalfScroll]")
    end

    test "only a top-200 hero qualifies and the empty hero leaderboard stays usable", %{conn: conn} do
      hero = create_base_hero() |> Game.update_hero!(%{pve_ranking: 201})
      Cachex.put(:game_cache, "pve_ranking", [Game.get_hero!(hero.id)])
      {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/player/#{hero.player_id}")
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")
      view |> element("#profile-ranking-hero") |> render_click()
      assert has_element?(view, "#profile-no-ranked-heroes")
      refute has_element?(view, "#profile-ranked-hero-#{hero.id}")
    end

    test "another profile's heroes are highlighted instead of the viewer's, with only its best hero scrolled into view",
         %{conn: conn} do
      viewer = create_base_hero() |> Game.update_hero!(%{pve_ranking: 1})
      profile_hero = create_base_hero() |> Game.update_hero!(%{pve_ranking: 50})

      second =
        Game.create_hero!(%{name: "Second ranked hero"}, profile_hero.player, base_avatar(), base_skills())
        |> Game.update_hero!(%{pve_ranking: 100})

      Cachex.put(:game_cache, "pve_ranking", Enum.map([viewer, profile_hero, second], &Game.get_hero!(&1.id)))
      {:ok, view, _} = live(init_test_session(conn, player_id: viewer.player_id), "/player/#{profile_hero.player_id}")
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")
      view |> element("#profile-ranking-hero") |> render_click()
      assert has_element?(view, "#profile-ranking-hero[aria-pressed=true]")
      assert has_element?(view, "#profile-ranked-hero-#{profile_hero.id}.selected-player[phx-hook=HalfScroll]")
      assert has_element?(view, "#profile-ranked-hero-#{second.id}.selected-player")
      refute has_element?(view, "#profile-ranked-hero-#{second.id}[phx-hook=HalfScroll]")
      refute has_element?(view, "#profile-ranked-hero-#{viewer.id}.selected-player")

      updated = Game.update_hero!(profile_hero, %{total_gold_farm: 500})
      Cachex.put(:game_cache, "pve_ranking", Enum.map([viewer, updated, second], &Game.get_hero!(&1.id)))
      send(view.pid, {"ranking", %{}})
      assert has_element?(view, "#profile-ranked-hero-#{profile_hero.id} .profile-hero-farm", "500")
      assert has_element?(view, "#profile-ranking-hero[aria-pressed=true]")
    end
  end
end
