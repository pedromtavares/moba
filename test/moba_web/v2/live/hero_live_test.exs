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

      {:ok, view, html} = live(conn, "/v2/hero/#{hero.id}")

      assert html =~ hero.name
      assert has_element?(view, "#hero-review")
      assert has_element?(view, "#ranking-card")
      assert has_element?(view, "a[href='/v2/player/#{hero.player_id}']")
    end

    test "owner sees skin controls", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, _view, html} = live(conn, "/v2/hero/#{hero.id}")

      assert html =~ "View Skins"
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

      {:ok, view, _html} = live(conn, "/v2/hero/#{hero.id}")

      html = render_click(view, "set-skin", %{"skin-code" => default_skin.code})
      assert html =~ hero.name
    end
  end
end
