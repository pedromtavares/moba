defmodule MobaWeb.DashboardLiveViewTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    %{user: pvp_user} = create_pvp_hero()

    pvp_user = Accounts.get_user!(pvp_user.id)
    conn = Pow.Plug.assign_current_user(conn, pvp_user, otp_app: :moba) |> init_test_session(current_mode: "pvp")

    {:ok, _view, html} = live(conn, "/base")
    assert html =~ "Arena"
  end
end
