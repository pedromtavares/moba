defmodule MobaWeb.V2.HeroLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "connected mount" do
    test "renders hero page content", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/hero/#{hero.id}")

      assert html =~ hero.name
      assert has_element?(view, "#hero-review")
      assert has_element?(view, "#ranking-card")
      assert has_element?(view, "a[href='/player/#{hero.player_id}']")
      assert has_element?(view, ".hero-stats .text-danger[title='Health']")
      assert has_element?(view, ".hero-stats .text-orange[title='Speed']")
    end

    test "owner sees skin controls", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/hero/#{hero.id}")

      assert html =~ "View Skins"
      assert has_element?(view, "#hero-bar")
      assert has_element?(view, "#toggle-shop")
    end

    test "non-owner does not see editable hero bar", %{conn: conn} do
      hero = create_base_hero()
      viewer = create_base_hero()

      conn =
        conn
        |> log_in_user(viewer.player.user)
        |> put_session(:player_id, viewer.player_id)

      {:ok, view, _html} = live(conn, "/hero/#{hero.id}")

      refute has_element?(view, "#hero-bar")
      refute has_element?(view, "#toggle-shop")
    end
  end

  describe "set-skin event" do
    test "updates skin selection without crashing", %{conn: conn} do
      hero = create_base_hero()
      default_skin = Game.default_skin(hero.avatar.code)

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/hero/#{hero.id}")

      html = render_click(view, "set-skin", %{"skin-code" => default_skin.code})
      assert html =~ hero.name
    end
  end

  test "owner can switch hero bar into edit mode and toggle the shop", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/hero/#{hero.id}")

    view
    |> element("#hero-bar #edit-button")
    |> render_click()

    assert has_element?(view, "#hero-bar #save-button")

    view
    |> element("#hero-bar #toggle-shop")
    |> render_click()

    assert has_element?(view, "#shop-modal.d-block")
  end
end
