defmodule MobaWeb.V2.PreviewLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest
  import Moba.AccountsFixtures

  test "canonical routes render the redesign and old preview bookmarks redirect", %{conn: conn} do
    hero = create_base_hero()
    player = Game.get_player!(hero.player_id)
    finished = create_base_hero(%{finished_at: Timex.now()}, player)
    Game.update_hero_collection!(finished)
    Game.set_current_pve_hero!(Game.get_player!(player.id), hero.id)
    conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)

    for {path, selector} <- [
          {"/base", "#base-page.base-page"},
          {"/invoke", "#invoke-modern"},
          {"/training", ".training"},
          {"/battles", "#battle-history"},
          {"/arena", ".arena-cinematic"},
          {"/arena/edit", "#teams-hud"},
          {"/library", "#manual-heading"},
          {"/community", "#community-heading"},
          {"/player/#{player.id}", "#profile-cinematic"},
          {"/hero/#{hero.id}", "#hero-detail"},
          {"/tavern", "#tavern"}
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#game-page .base-atmosphere[aria-hidden=true]")
      assert has_element?(view, "#game-page #{selector}"), path
      assert has_element?(view, ".stats-footer") == (path == "/community")
      refute has_element?(view, "a[href^='/new/'], form[action^='/new/']")
      assert has_element?(view, "#game-sidebar a[href='/base']")
      assert has_element?(view, "#game-sidebar a[href='/arena']")
      assert conn |> get("/new" <> path) |> redirected_to(301) == path
    end
  end

  test "navigation and continue use canonical routes", %{conn: conn} do
    hero = create_base_hero()
    finished = create_base_hero(%{finished_at: Timex.now()}, Game.get_player!(hero.player_id))
    Game.update_hero_collection!(finished)
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/base")

    {:ok, view, _} =
      view |> element(".sidebar-nav a[href='/arena']") |> render_click() |> follow_redirect(conn, "/arena")

    assert has_element?(view, "#game-page #enter-arena-button")
    assert has_element?(view, "#arena-entry-reward")
    refute has_element?(view, "#enter-arena-button .badge")
    assert has_element?(view, "#arena-progress-label")

    {:ok, view, _} =
      view |> element(".sidebar-nav a[href='/base']") |> render_click() |> follow_redirect(conn, "/base")

    assert has_element?(view, "#game-page #base-invoke-btn[href='/invoke']")
    view |> element("#visible-hero-#{hero.id} [phx-click=continue]") |> render_click()
    assert_redirect(view, "/training")
  end

  test "canonical battles, duels and matches retain combat and picking controls", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_base_hero()
    battle = create_basic_battle(hero, opponent)
    duel = Game.create_duel!(hero.player, opponent.player, false)

    match =
      Moba.Game.Matches.create!(%{
        player_id: hero.player_id,
        opponent_id: opponent.player_id,
        player_picks: [],
        opponent_picks: [opponent.id],
        generated_picks: [],
        type: "manual"
      })

    conn = conn |> init_test_session(player_id: hero.player_id)

    for {path, selector} <- [
          {"/battles/#{battle.id}", "#battle-page"},
          {"/arena/#{duel.id}", "#battle-bar"},
          {"/matches/#{match.id}", "#picks-card"}
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#game-page #{selector}")
      assert has_element?(view, ".hero-card")
      refute has_element?(view, "button.game-stat, .hero-stats button, .battle-stat-group button")

      if selector == "#battle-page" do
        assert has_element?(view, ".battle-stat-group span.game-stat[title^='ATK:'] .stat-value")
        assert has_element?(view, ".battle-stat-group .stat-label", "Attack")
      end
    end
  end

  test "guest creation submits and redirects through canonical routes", %{conn: conn} do
    {:ok, view, _} = live(conn, "/start")
    view |> render_click("pick-avatar", %{"id" => base_avatar().id})

    assert view
           |> element("#create-new")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query(".invoke-base-stats > div")
           |> Enum.count() == 6

    refute has_element?(view, "#create-new button.avatar-attribute")
    view |> render_click("pick-build", %{"number" => "0"})
    assert has_element?(view, "#game-page form[action='/start'] #create-button")

    conn = conn |> get("/start") |> recycle()

    response =
      post(conn, "/start", %{
        "avatar" => base_avatar().id,
        "skills" => Enum.map(base_skills(), & &1.id)
      })

    assert redirected_to(response) == "/training"
  end

  test "tavern tabs expose the current collection", %{conn: conn} do
    hero = create_base_hero()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/tavern")
    assert has_element?(view, "#show-avatars-link[aria-selected=true]")
    view |> element("#show-skills-link") |> render_click()
    assert has_element?(view, "#show-skills-link[aria-selected=true]")
    assert has_element?(view, "#show-avatars-link[aria-selected=false]")
    view |> element("#show-skins-link") |> render_click()
    assert has_element?(view, "#show-skins-link[aria-selected=true]")
  end

  test "profile switches ranking through the period controls", %{conn: conn} do
    hero = create_base_hero()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/player/#{hero.player_id}")

    assert has_element?(view, "#profile-ranking-daily[aria-pressed=true]")
    assert has_element?(view, "#profile-ranking-header", "Daily wins")

    view |> element("#profile-ranking-season") |> render_click()
    assert has_element?(view, "#profile-ranking-season[aria-pressed=true]")
    assert has_element?(view, "#profile-ranking-header", "Season score")

    view |> element("#profile-ranking-daily") |> render_click()
    assert has_element?(view, "#profile-ranking-daily[aria-pressed=true]")
  end

  test "account screens render the redesign and login returns to canonical routes", %{conn: conn} do
    user = user_fixture()

    for {path, selector} <- [
          {"/users/register", "#registration_form"},
          {"/users/reset_password", "#reset_password_form"},
          {"/users/confirm", "#resend_confirmation_form"}
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#game-page #{selector}")
    end

    {:ok, view, _} = live(conn, "/users/log_in")
    assert has_element?(view, "#login_form[action='/users/log_in']")

    response =
      view |> form("#login_form", user: %{email: user.email, password: valid_user_password()}) |> submit_form(conn)

    assert redirected_to(response) == "/base"
    assert response |> recycle() |> delete("/users/log_out") |> redirected_to() == "/"

    {:ok, settings, _} = conn |> log_in_user(user) |> live("/users/settings")
    assert has_element?(settings, "#game-page #settings_form")
    assert has_element?(settings, "a[href='/user/#{user.id}']")
  end

  test "canonical access without a player returns to the picker", %{conn: conn} do
    response = get(conn, "/base")
    assert redirected_to(response) == "/start"
  end
end
