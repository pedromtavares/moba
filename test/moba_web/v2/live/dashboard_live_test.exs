defmodule MobaWeb.V2.DashboardLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "unauthenticated access" do
    test "redirects to /start without player_id in session", %{conn: conn} do
      conn = get(conn, "/v2/base")
      assert redirected_to(conn) == "/start"
    end
  end

  describe "connected mount" do
    test "renders pve progression and hero list", %{conn: conn} do
      hero = create_base_hero()
      conn = init_test_session(conn, player_id: hero.player_id)

      {:ok, _view, html} = live(conn, "/v2/base")

      assert html =~ "Train a new Hero"
      assert html =~ "In Progress"
      assert html =~ "Finished"
      assert html =~ "id=\"pve-progression\""
    end

    test "shows unfinished heroes by default when they exist", %{conn: conn} do
      hero = create_base_hero()
      conn = init_test_session(conn, player_id: hero.player_id)

      {:ok, view, _html} = live(conn, "/v2/base")

      assert has_element?(view, "#hero-card-#{hero.id}")
    end

    test "renders sidebar with player info", %{conn: conn} do
      hero = create_base_hero()
      conn = init_test_session(conn, player_id: hero.player_id)

      {:ok, view, _html} = live(conn, "/v2/base")

      assert has_element?(view, "[data-role=sidebar]")
    end
  end

  describe "filter event" do
    test "switches to finished tab", %{conn: conn} do
      hero = create_base_hero()
      conn = init_test_session(conn, player_id: hero.player_id)

      {:ok, view, _html} = live(conn, "/v2/base")

      render_click(view, :filter, %{"filter" => "finished"})

      refute has_element?(view, "#hero-card-#{hero.id}")
    end

    test "switches back to unfinished tab", %{conn: conn} do
      hero = create_base_hero()
      conn = init_test_session(conn, player_id: hero.player_id)

      {:ok, view, _html} = live(conn, "/v2/base")

      render_click(view, :filter, %{"filter" => "finished"})
      render_click(view, :filter, %{"filter" => "unfinished"})

      assert has_element?(view, "#hero-card-#{hero.id}")
    end
  end

  describe "toggle-rewards event" do
    test "shows and hides progression rewards panel", %{conn: conn} do
      hero = create_base_hero()
      conn = init_test_session(conn, player_id: hero.player_id)

      {:ok, view, html} = live(conn, "/v2/base")

      refute html =~ "pve-tier-rewards"

      html = render_click(view, "toggle-rewards")
      assert html =~ "pve-tier-rewards"
      assert html =~ "Progression Rewards"

      html = render_click(view, "toggle-rewards")
      refute html =~ "pve-tier-rewards"
    end
  end

  describe "continue event" do
    test "redirects to v1 training", %{conn: conn} do
      hero = create_base_hero()
      conn = init_test_session(conn, player_id: hero.player_id)

      {:ok, view, _html} = live(conn, "/v2/base")

      assert {:error, {:redirect, %{to: "/training"}}} =
               view
               |> element("#hero-card-#{hero.id} [phx-click=continue]")
               |> render_click()
    end
  end

  describe "archive event" do
    test "removes hero from the list", %{conn: conn} do
      hero = create_base_hero()
      conn = init_test_session(conn, player_id: hero.player_id)

      {:ok, view, _html} = live(conn, "/v2/base")

      view
      |> element("#hero-card-#{hero.id} [phx-click=archive]")
      |> render_click()

      refute has_element?(view, "#hero-card-#{hero.id}")
    end
  end
end
