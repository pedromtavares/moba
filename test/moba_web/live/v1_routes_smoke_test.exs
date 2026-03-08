defmodule MobaWeb.V1RoutesSmokeTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "arena index mounts under /v1", %{conn: conn} do
    hero = create_base_hero()
    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, _view, html} = live(conn, "/v1/arena")

    assert html =~ "pvp-progression"
  end

  test "hero show mounts under /v1", %{conn: conn} do
    hero = create_base_hero()
    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, _view, html} = live(conn, "/v1/hero/#{hero.id}")

    assert html =~ hero.name
  end
end
