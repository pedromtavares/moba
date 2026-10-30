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
    assert has_element?(view, "#history-ganks-title")
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
      |> element("#replay-battle-#{battle.id}")
      |> render_click()
      |> follow_redirect(conn)

    assert battle_html =~ "Training battle initiated by"
  end

  test "preview history has useful empty states and returns to training", %{conn: conn} do
    hero = create_base_hero()
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/battles")

    refute has_element?(view, ".history-heading")
    assert has_element?(view, "#history-ganks-title", "Battles")
    assert has_element?(view, "#history-league-title", "League Challenge")
    assert has_element?(view, "#history-ganks-empty")
    assert has_element?(view, "#history-league-empty")
    assert has_element?(view, "#current-training-rank .league-logo")
    assert has_element?(view, "#history-return-training[href='/training']")
    view |> element("#history-return-training") |> render_click()
    assert_redirect(view, "/training")
  end

  test "preview shows the recorded result and rewards and opens its replay", %{conn: conn} do
    hero = create_base_hero()
    Game.generate_targets!(hero)
    target = hero |> Game.list_targets() |> List.first() |> then(&Game.get_target!(&1.id))
    battle = target |> Game.start_pve_battle!() |> Engine.auto_finish_battle!()
    battle = Engine.update_battle!(battle, %{defender_snapshot: %{level: battle.defender.level}})
    Game.update_hero!(battle.defender, %{level: battle.defender_snapshot.level + 10})
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/battles")

    result =
      cond do
        is_nil(battle.winner_id) -> "TIE"
        battle.winner_id == hero.id -> "WIN"
        true -> "LOSS"
      end

    refute has_element?(view, "#history-ganks-empty")
    assert has_element?(view, "#battle-#{battle.id} .history-outcome[data-result='#{result}']")
    assert has_element?(view, "#battle-#{battle.id} .history-opponent", battle.defender.name)
    assert has_element?(view, "#battle-#{battle.id} .history-opponent small", "Lv #{battle.defender_snapshot.level}")
    assert has_element?(view, "#battle-#{battle.id} .history-time")

    if battle.rewards.total_xp > 0 do
      assert has_element?(view, "#battle-#{battle.id} .history-xp", "+#{battle.rewards.total_xp} XP")
      assert has_element?(view, "#battle-#{battle.id} .history-gold", "+#{battle.rewards.total_gold}g")
    else
      assert has_element?(view, "#battle-#{battle.id} .history-no-reward")
    end

    view |> element("#replay-battle-#{battle.id}") |> render_click()
    assert_redirect(view, "/battles/#{battle.id}")
  end

  test "preview league history distinguishes cleared steps from promotions", %{conn: conn} do
    hero = create_base_hero(%{league_tier: 0, league_step: 1}, create_player!(), strong_avatar())
    cleared = hero |> Game.start_league_battle!() |> Engine.auto_finish_battle!()
    hero = Game.get_hero!(hero.id)
    promoted = hero |> Game.start_league_battle!() |> Engine.auto_finish_battle!()
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/battles")

    refute has_element?(view, "#history-league-empty")
    assert has_element?(view, "#battle-#{cleared.id} .history-step-win", "Battle 1 cleared")
    assert has_element?(view, "#battle-#{promoted.id} .history-promotion", "Promoted")
    assert has_element?(view, "#replay-battle-#{promoted.id}[href='/battles/#{promoted.id}']")
  end

  test "redirects to /base when player has no current hero", %{conn: conn} do
    player = create_player!(%{current_pve_hero_id: nil})

    conn =
      conn
      |> init_test_session(player_id: player.id)

    live(conn, "/battles") |> follow_redirect(conn, "/base")
  end
end
