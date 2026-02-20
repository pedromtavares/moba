defmodule MobaWeb.DashboardLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    %{player_id: player_id} = create_base_hero()

    conn = init_test_session(conn, player_id: player_id)

    {:ok, _view, html} = live(conn, "/base")
    assert html =~ "Train a new Hero"
  end
end
