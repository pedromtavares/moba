defmodule MobaWeb.MatchLiveViewTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    # slows down suite by 1 sec
    Game.Matches.start!(0..0)

    {:ok, _view, html} = live(conn, "/match")
    assert html =~ "Previous Match"

    # post reset redirects
    live(conn, "/jungle") |> follow_redirect(conn, "/match")
    live(conn, "/arena") |> follow_redirect(conn, "/match")
  end
end
