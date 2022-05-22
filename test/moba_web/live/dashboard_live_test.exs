defmodule MobaWeb.DashboardLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    %{user: pve_user} = create_base_hero()

    pve_user = Accounts.get_user!(pve_user.id)
    conn = Pow.Plug.assign_current_user(conn, pve_user, otp_app: :moba) |> init_test_session(%{})

    {:ok, _view, html} = live(conn, "/base")
    assert html =~ "Train a new Hero"
  end
end
