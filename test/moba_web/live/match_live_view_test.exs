defmodule MobaWeb.MatchLiveViewTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    %{user: pvp_user} = create_pvp_hero()

    # slows down suite by 1 sec
    Conductor.start_match!()

    pvp_user = Accounts.get_user!(pvp_user.id)
    conn = Pow.Plug.assign_current_user(conn, pvp_user, otp_app: :moba) |> init_test_session(current_mode: "pvp")

    {:ok, _view, html} = live(conn, "/match")
    assert html =~ "Previous Match"

    live(conn, "/arena") |> follow_redirect(conn, "/match")
  end
end
