defmodule MobaWeb.V2.BattlesLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders battles history at /v2/battles", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, _view, html} = live(conn, "/v2/battles")

    assert html =~ "Return to Training"
    assert html =~ "Wins/Losses"
    assert html =~ "League Challenge"
  end

  test "redirects to /v2/base when player has no current hero", %{conn: conn} do
    player = create_player!(%{current_pve_hero_id: nil})

    conn =
      conn
      |> init_test_session(player_id: player.id)

    live(conn, "/v2/battles") |> follow_redirect(conn, "/v2/base")
  end
end
