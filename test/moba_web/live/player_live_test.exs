defmodule MobaWeb.PlayerLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.player.user, otp_app: :moba)

    username = hero.player.user.username

    {:ok, _view, html} = live(conn, "/player/#{hero.player_id}")
    assert html =~ username
  end
end
