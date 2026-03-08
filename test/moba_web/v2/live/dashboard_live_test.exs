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
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, _view, html} = live(conn, "/base")

      assert html =~ "Train a new Hero"
      assert html =~ "In Progress"
      assert html =~ "Finished"
      assert html =~ "id=\"pve-progression\""
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
  end

  describe "filter event" do
    test "switches to finished tab", %{conn: conn} do
      player = create_player!()
      _unfinished = create_base_hero(%{name: "In Progress"}, player)
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

  describe "rewards modal" do
    test "renders the progression rewards modal and trigger", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/base")

      assert html =~ "pve-tier-rewards"
      assert html =~ "Progression Rewards"
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
end
