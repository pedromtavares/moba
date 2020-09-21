defmodule MobaWeb.MatchLiveViewTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero_with_ganks = create_base_hero()
    hero_without_ganks = create_base_hero(%{pve_battles_available: 0})

    conn = Pow.Plug.assign_current_user(conn, hero_without_ganks.user, otp_app: :moba)

    # slows down suite by 1 sec
    Game.Matches.start!(0..0)

    {:ok, _view, html} = live(conn, "/match")
    assert html =~ "Previous Match"

    # post reset redirects
    live(conn, "/jungle") |> follow_redirect(conn, "/match")
    live(conn, "/arena") |> follow_redirect(conn, "/match")

    conn = Pow.Plug.assign_current_user(conn, hero_with_ganks.user, otp_app: :moba)

    {:ok, _view, html} = live(conn, "/match")
    assert html =~ "Previous Match"

    # post reset redirects
    {:ok, _view, html} = live(conn, "/jungle")
    assert html =~ "Jungle"
    live(conn, "/arena") |> follow_redirect(conn, "/jungle")
  end
end
