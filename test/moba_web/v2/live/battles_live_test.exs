defmodule MobaWeb.V2.BattlesLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders battles history at /battles", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, view, html} = live(conn, "/battles")

    assert html =~ "Return to Training"
    assert html =~ "Wins/Losses"
    assert html =~ "League Challenge"
    assert has_element?(view, "#current-training-rank .league-logo")
  end

  test "clicking a battle row navigates to the battle page", %{conn: conn} do
    hero = create_base_hero()
    Game.generate_targets!(hero)
    target = hero |> Game.list_targets() |> List.first() |> then(&Game.get_target!(&1.id))
    battle = target |> Game.start_pve_battle!() |> Engine.auto_finish_battle!()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/battles")

    {:ok, _battle_view, battle_html} =
      view
      |> element("#battle-#{battle.id}")
      |> render_click()
      |> follow_redirect(conn)

    assert battle_html =~ "Battle initiated by"
  end

  test "redirects to /base when player has no current hero", %{conn: conn} do
    player = create_player!(%{current_pve_hero_id: nil})

    conn =
      conn
      |> init_test_session(player_id: player.id)

    live(conn, "/battles") |> follow_redirect(conn, "/base")
  end
end
