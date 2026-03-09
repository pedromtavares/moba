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
      assert has_element?(view, "#loading-ranking")
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

  describe "set-featured event" do
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
    test "toggles from daily to season ranking", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/player/#{hero.player_id}")
      assert html =~ "Daily Rank"

      html = render_click(view, "switch-ranking")
      assert html =~ "Season Rank"
      assert html =~ "Season Score"
    end
  end
end
