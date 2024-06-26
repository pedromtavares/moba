defmodule MobaWeb.BattleLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    attacker = create_base_hero()

    defender = create_base_hero()

    battle = create_basic_battle(attacker, defender)

    conn =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(player_id: attacker.player_id)

    %{conn: conn, battle: battle, attacker: attacker, defender: defender}
  end

  test "connected mount", %{conn: conn, battle: battle} do
    {:ok, _view, html} = live(conn, "/battles/#{battle.id}")
    assert html =~ "Click to select a skill"
  end

  # This test sometimes prints out
  # [error] Postgrex.Protocol (#PID<0.867.0>) disconnected: ** (DBConnection.ConnectionError) owner #PID<0.2148.0> exited
  # Client #PID<0.2253.0> is still using a connection from owner at location
  test "next turn event", %{conn: conn, battle: battle, attacker: attacker} do
    skill = base_skill()
    {:ok, view, _html} = live(conn, "/battles/#{battle.id}")

    assert render_click(view, "next-turn", %{"skill_id" => skill.id, "item_id" => "", "hero_id" => attacker.id}) =~
             "used #{skill.name}"
  end
end
