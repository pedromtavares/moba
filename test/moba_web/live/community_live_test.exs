defmodule MobaWeb.CommunityLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.player.user, otp_app: :moba)

    {:ok, _view, html} = live(conn, "/community")
    assert html =~ "Ranking"
  end
end
