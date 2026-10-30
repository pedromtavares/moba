defmodule MobaWeb.V2.DashboardLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "unauthenticated access" do
    test "redirects to /start without player_id in session", %{conn: conn} do
      conn = get(conn, "/base")
      assert redirected_to(conn) == "/start"
    end
  end

  describe "connected mount" do
    test "renders pve progression and hero list", %{conn: conn} do
      hero =
        create_base_hero()
        |> Game.buy_item!(base_item())

      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/base")

      assert html =~ "Train a new Hero"
      assert html =~ "In Progress"
      assert html =~ "Finished"
      assert html =~ "id=\"pve-progression\""
      assert has_element?(view, "#visible-hero-#{hero.id} .league-logo")
      assert has_element?(view, "#skill-#{hd(hero.skills).id}-#{hero.id}[title]")
      assert has_element?(view, "#item-#{hd(hero.items).id}-#{hero.id}[title]")
    end

    test "shows unfinished heroes by default when they exist", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/base")

      assert has_element?(view, "#visible-hero-#{hero.id}")
    end

    test "renders the dashboard navigation controls", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/base")

      assert has_element?(view, "#finished-heroes-btn")
      assert has_element?(view, "#hero-list-unfinished")
    end

    test "starts the base tutorial when the player is on step 19", %{conn: conn} do
      hero = create_base_hero()
      player = Game.update_tutorial_step!(hero.player, 19)
      conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)

      {:ok, view, _html} = live(conn, "/base")

      assert has_element?(view, "#tutorial-step-20[data-step='20']")
    end

    test "guest base tutorial keeps the v1 anchor targets", %{conn: conn} do
      player = Game.create_player!(%{user_id: nil, tutorial_step: 20})
      hero = create_base_hero(%{name: "Guest Hero"}, player)
      player = Game.update_collection!(player, [%{id: hero.id}])
      conn = conn |> init_test_session(player_id: player.id)

      {:ok, view, _html} = live(conn, "/base")

      assert has_element?(view, "#hero-list-container")
      assert has_element?(view, "#create-account-link")
      assert has_element?(view, "#tutorial-step-20[data-step='20']")
    end
  end

  describe "filter event" do
    test "switches to finished tab", %{conn: conn} do
      player = create_player!()
      _unfinished = create_base_hero(%{name: "In Progress"}, player)
      player = Game.get_player!(player.id)
      finished = create_base_hero(%{name: "Finished"}, player) |> Game.update_hero!(%{finished_at: Timex.now()})
      user = Accounts.get_user!(player.user_id)

      conn = conn |> log_in_user(user) |> put_session(:player_id, player.id)

      {:ok, view, _html} = live(conn, "/base")

      render_click(view, "show-finished", %{})

      assert has_element?(view, "#hero-list-finished")
      assert has_element?(view, "#visible-hero-#{finished.id}")
      refute has_element?(view, "#visible-hero-#{player.current_pve_hero_id}")
    end

    test "switches back to unfinished tab", %{conn: conn} do
      player = create_player!()
      unfinished = create_base_hero(%{name: "In Progress"}, player)
      player = Game.get_player!(player.id)
      _finished = create_base_hero(%{name: "Finished"}, player) |> Game.update_hero!(%{finished_at: Timex.now()})
      user = Accounts.get_user!(player.user_id)

      conn = conn |> log_in_user(user) |> put_session(:player_id, player.id)

      {:ok, view, _html} = live(conn, "/base")

      render_click(view, "show-finished", %{})
      render_click(view, "show-unfinished", %{})

      assert has_element?(view, "#hero-list-unfinished")
      assert has_element?(view, "#visible-hero-#{unfinished.id}")
    end
  end

  describe "cinematic base" do
    test "renders the redesigned progression and preserves collection filters", %{conn: conn} do
      hero = create_base_hero() |> Game.buy_item!(base_item())
      player = Game.get_player!(hero.player_id)
      finished = create_base_hero(%{name: "Finished Hero"}, player) |> Game.update_hero!(%{finished_at: Timex.now()})
      Game.update_hero_collection!(finished)
      conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)

      {:ok, preview, _html} = live(conn, "/base")
      assert has_element?(preview, "#game-page .base-atmosphere[aria-hidden=true]")
      assert has_element?(preview, "#hero-list-container")

      assert has_element?(preview, "#pve-progression.base-ascent")
      assert has_element?(preview, "#base-rank-0[aria-current=step]")
      assert has_element?(preview, "#base-rank-1.is-next")

      refute has_element?(preview, ".stats-footer")
      assert has_element?(preview, "#skill-#{hd(hero.skills).id}-#{hero.id}[title]")
      assert has_element?(preview, "#item-#{hd(hero.items).id}-#{hero.id}[title]")

      preview |> element("#finished-heroes-btn") |> render_click()
      assert has_element?(preview, "#active-finished-heroes-btn[aria-pressed=true]")
      assert has_element?(preview, "#visible-hero-#{finished.id}")
      refute has_element?(preview, "#visible-hero-#{hero.id}")

      preview |> element("#in-progress-heroes-btn") |> render_click()
      assert has_element?(preview, "#base-page.base-page #visible-hero-#{hero.id}")
      assert has_element?(preview, "#active-in-progress-heroes-btn[aria-pressed=true]")
    end
  end

  test "cinematic progression retains advanced requirements and the final rank", %{conn: conn} do
    player = create_player!(%{pve_tier: 4, pve_progression: %{master_codes: ["phantom_assassin"]}})
    hero = create_base_hero(%{}, player)
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/base")

    assert has_element?(view, "#base-rank-4[aria-current=step]")
    assert has_element?(view, "#base-rank-5.is-next")
    assert has_element?(view, "#base-quest-description", "20 different Avatars")
    assert has_element?(view, "#base-rank-progress[aria-valuetext='1/20 Avatars'][aria-valuenow='5']")
    assert has_element?(view, "#base-rewards-btn[data-target='#pve-tier-rewards']")

    Game.update_player!(player, %{pve_tier: Moba.max_pve_tier()})
    {:ok, finished, _} = live(conn, "/base")
    assert has_element?(finished, "#base-rank-7[aria-current=step]")
    assert has_element?(finished, "#base-ascent-complete")
    refute has_element?(finished, "#base-rank-progress, #base-rewards-btn, #base-rank-8")
  end

  describe "rewards modal" do
    test "renders the progression rewards modal and trigger", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/base")

      assert html =~ "pve-tier-rewards"
      assert has_element?(view, "#base-rewards-btn[data-target='#pve-tier-rewards']")
      assert has_element?(view, "button[data-target='#pve-tier-rewards']")
    end
  end

  describe "continue event" do
    test "redirects to v2 training", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/base")

      assert {:error, {:redirect, %{to: "/training"}}} =
               view
               |> element("#visible-hero-#{hero.id} [phx-click=continue]")
               |> render_click()
    end
  end

  describe "archive event" do
    test "removes hero from the list", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/base")

      view
      |> element("#visible-hero-#{hero.id} [phx-click=archive]")
      |> render_click()

      refute has_element?(view, "#visible-hero-#{hero.id}")
    end
  end

  describe "tutorial events" do
    test "advances from step 20 to 21", %{conn: conn} do
      hero = create_base_hero()
      player = Game.update_tutorial_step!(hero.player, 20)
      conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)

      {:ok, view, _html} = live(conn, "/base")

      render_click(view, "tutorial1", %{})

      assert has_element?(view, "#tutorial-step-21[data-step='21']")
    end

    test "finish-tutorial completes the base tutorial", %{conn: conn} do
      hero = create_base_hero()
      player = Game.update_tutorial_step!(hero.player, 21)
      conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)

      {:ok, view, _html} = live(conn, "/base")

      render_click(view, "finish-tutorial", %{})

      assert Game.get_player!(player.id).tutorial_step == 39
      assert has_element?(view, "#tutorial-step-39[data-step='39']")
    end
  end
end
