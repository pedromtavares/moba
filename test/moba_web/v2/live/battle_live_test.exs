defmodule MobaWeb.V2.BattleLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Moba.Game.Matches

  setup do
    attacker = create_base_hero()
    defender = create_base_hero()
    battle = create_basic_battle(attacker, defender)

    conn =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(player_id: attacker.player_id)

    %{conn: conn, battle: battle, attacker: attacker}
  end

  test "connected mount", %{conn: conn, battle: battle} do
    {:ok, view, html} = live(conn, "/battles/#{battle.id}")
    assert html =~ "Click to select a skill"
    assert has_element?(view, ~s|#battle-page[phx-hook="BattleContinueHotkey"]|)
  end

  test "next turn event", %{conn: conn, battle: battle, attacker: attacker} do
    skill = base_skill()
    {:ok, view, _html} = live(conn, "/battles/#{battle.id}")

    assert render_click(view, "next-turn", %{"skill_id" => skill.id, "item_id" => "", "hero_id" => attacker.id}) =~
             "used #{skill.name}"
  end

  test "league rewards use the updated snapshot after finishing a turn", %{conn: conn} do
    player = create_player!(%{user_id: nil})

    attacker =
      create_base_hero(%{league_tier: 0, league_step: 2}, player, strong_avatar())
      |> Moba.Repo.preload(:skills)

    battle = Game.start_league_battle!(attacker)
    skill_id = attacker.skills |> List.first() |> Map.fetch!(:id)

    conn =
      conn
      |> init_test_session(player_id: attacker.player_id)

    {:ok, view, _html} = live(conn, "/battles/#{battle.id}")
    rewards_html = play_until_finished(view, battle.id, attacker.id, skill_id, 20)

    finished = Engine.get_battle!(battle.id)
    assert finished.finished
    assert finished.type == "league"
    assert rewards_html =~ "GG! You have beaten the League Challenge and are now in a higher league!"
    refute rewards_html =~ "Proceed to Battle"
  end

  test "finished duel battle links back to the duel", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    skills = base_skills()

    player_hero = Game.create_hero!(%{name: "Player Hero"}, player, strong_avatar(), skills)
    opponent_hero = Game.create_hero!(%{name: "Opponent Hero"}, opponent, weak_avatar(), skills)

    duel = Game.create_duel!(player, opponent, false)
    Game.continue_duel!(duel, player_hero)
    duel = Game.get_duel!(duel.id)
    Game.continue_duel!(duel, opponent_hero)
    duel = Game.get_duel!(duel.id)
    battle = Engine.first_duel_battle(duel)
    battle = Engine.auto_finish_battle!(battle)

    conn =
      conn
      |> init_test_session(player_id: player.id)

    {:ok, view, _html} = live(conn, "/battles/#{battle.id}")

    assert has_element?(view, ~s|#battle-over-duel[href="/arena/#{duel.id}"]|)
    assert has_element?(view, ~s|#load-battles[href="/arena/#{duel.id}"]|)
  end

  test "finished match battle links back to the match", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    skills = base_skills()

    player_hero = Game.create_hero!(%{name: "Player Hero"}, player, strong_avatar(), skills)
    opponent_hero = Game.create_hero!(%{name: "Opponent Hero"}, opponent, weak_avatar(), skills)

    match =
      Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [player_hero.id],
        opponent_picks: [opponent_hero.id],
        generated_picks: [],
        type: "manual"
      })

    battle =
      Engine.create_match_battle!(%{
        attacker: opponent_hero,
        attacker_player: opponent,
        defender: player_hero,
        defender_player: player,
        match: match
      })
      |> Engine.auto_finish_battle!()

    conn =
      conn
      |> init_test_session(player_id: player.id)

    {:ok, view, _html} = live(conn, "/battles/#{battle.id}")

    assert has_element?(view, ~s|#load-battles[href="/matches/#{match.id}"]|)
  end

  defp play_until_finished(view, battle_id, attacker_id, skill_id, attempts_left) when attempts_left > 0 do
    _html =
      render_click(view, "next-turn", %{
        "skill_id" => skill_id,
        "item_id" => "",
        "hero_id" => attacker_id
      })

    if Engine.get_battle!(battle_id).finished do
      render(view)
    else
      play_until_finished(view, battle_id, attacker_id, skill_id, attempts_left - 1)
    end
  end

  defp play_until_finished(_view, _battle_id, _attacker_id, _skill_id, 0) do
    flunk("league battle did not finish within expected number of turns")
  end
end
