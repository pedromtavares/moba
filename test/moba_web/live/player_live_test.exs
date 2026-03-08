defmodule MobaWeb.PlayerLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn = init_test_session(conn, player_id: hero.player_id)

    username = hero.player.user.username

    {:ok, _view, html} = live(conn, "/v1/player/#{hero.player_id}")
    assert html =~ username
  end
end
