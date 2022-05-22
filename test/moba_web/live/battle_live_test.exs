defmodule MobaWeb.BattleLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    attacker = create_base_hero()

    defender = create_base_hero()

    battle = create_basic_battle(attacker, defender)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Pow.Plug.assign_current_user(attacker.user, otp_app: :moba)

    %{conn: conn, battle: battle, attacker: attacker, defender: defender}
  end

  test "connected mount", %{conn: conn, battle: battle} do
    {:ok, _view, html} = live(conn, "/battles/#{battle.id}")
    assert html =~ "Click to select a skill"
  end

  test "next turn event", %{conn: conn, battle: battle, attacker: attacker} do
    skill = base_skill()
    {:ok, view, _html} = live(conn, "/battles/#{battle.id}")

    assert render_click(view, "next-turn", %{"skill_id" => skill.id, "item_id" => "", "hero_id" => attacker.id}) =~
             "used #{skill.name}"
  end
end
