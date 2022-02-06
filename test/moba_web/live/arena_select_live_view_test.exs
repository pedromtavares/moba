defmodule MobaWeb.ArenaSelectLiveViewTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero(%{league_tier: 5, finished_at: Timex.now()})

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    {:ok, _view, html} = live(conn, "/arena/select")
    assert html =~ "Enter the"
  end

  test "connected mount, redirects to arena if there is pvp hero", %{conn: conn} do
    hero = create_pvp_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    live(conn, "/arena/select") |> follow_redirect(conn, "/arena")
  end

  test "connected mount, redirects if match hasnt started", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    Admin.update_match(Game.current_match(), %{last_server_update_at: nil})

    live(conn, "/arena/select") |> follow_redirect(conn, "/base")
  end
end
