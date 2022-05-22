defmodule MobaWeb.UserLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    username = hero.user.username

    {:ok, _view, html} = live(conn, "/user/#{hero.user_id}")
    assert html =~ username
  end
end
