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
      second = create_base_hero(%{name: "Second hero", finished_at: Timex.now()}, Game.get_player!(first.player_id), strong_avatar())
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

  describe "switch-ranking event" do
    test "identifies each player's arena bracket in daily and season rankings", %{conn: conn} do
      pleb = create_player!(%{pvp_tier: 0, ranking: 26, season_ranking: 3})
      shadow = create_player!(%{pvp_tier: 1, ranking: 6, season_ranking: 2})
      immortal = create_player!(%{pvp_tier: 2, ranking: 1, season_ranking: 1})
      hero = create_base_hero(%{}, pleb)
      ranking = Enum.map([immortal, shadow, pleb], &Game.get_player!(&1.id))

      for key <- ["daily_ranking", "season_ranking"] do
        Cachex.put(:game_cache, key, ranking)
        on_exit(fn -> Cachex.del(:game_cache, key) end)
      end

      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, pleb.id)

      {:ok, view, _} = live(conn, "/player/#{hero.player_id}")

      for period <- ["daily", "season"] do
        if period == "season", do: view |> element("#profile-ranking-season") |> render_click()

        for {player, bracket} <- [{pleb, "Plebs"}, {shadow, "Shadows"}, {immortal, "Immortals"}] do
          assert has_element?(view, "#player-#{player.id}[data-bracket='#{bracket}'] .profile-ranking-bracket", bracket)
        end

        assert has_element?(view, "#player-#{pleb.id}.selected-player")
      end
    end

    test "preview period buttons switch the leaderboard in both directions", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, _} = live(conn, "/player/#{hero.player_id}")
      assert has_element?(view, "#profile-ranking-daily[disabled][aria-pressed='true']")
      assert has_element?(view, "#profile-ranking-header", "Daily wins")
      refute has_element?(view, "#loading-ranking")

      view |> element("#profile-ranking-season") |> render_click()
      assert has_element?(view, "#profile-ranking-season[disabled][aria-pressed='true']")
      assert has_element?(view, "#profile-ranking-header", "Season score")

      view |> element("#profile-ranking-daily") |> render_click()
      assert has_element?(view, "#profile-ranking-daily[disabled][aria-pressed='true']")
      assert has_element?(view, "#profile-ranking-header", "Daily wins")
    end

    test "toggles from daily to season ranking", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/player/#{hero.player_id}")
      assert html =~ "Daily wins"

      html = render_click(view, "switch-ranking")
      assert html =~ "Season score"
      assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")
    end
  end
end
