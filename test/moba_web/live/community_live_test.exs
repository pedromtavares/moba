defmodule MobaWeb.CommunityLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, _view, html} = live(conn, "/v1/community")
    assert html =~ "Message Board"
  end
end
