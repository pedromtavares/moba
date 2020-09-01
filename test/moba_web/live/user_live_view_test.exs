defmodule MobaWeb.UserLiveViewTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    username = hero.user.username

    {:ok, _view, html} = live(conn, "/user/#{username}")
    assert html =~ username
  end
end
