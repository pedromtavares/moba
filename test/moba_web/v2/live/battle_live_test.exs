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

  test "connected mount", %{conn: conn, battle: battle, attacker: attacker} do
    {:ok, view, html} = live(conn, "/battles/#{battle.id}")
    assert html =~ "Make your first move"
    assert has_element?(view, ~s|#battle-page[phx-hook="BattleContinueHotkey"]|)
    assert has_element?(view, ".hero-card .text-danger[title='Health']")
    assert has_element?(view, ".hero-card .text-orange[title='Speed']")
    assert has_element?(view, "#skill-#{hd(attacker.skills).id}-#{attacker.id}")
    assert has_element?(view, "[id^='active-skill-']")
    assert has_element?(view, "#pick-basic-attack[title]")
    assert has_element?(view, ".item-img.empty-item")
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
    assert has_element?(view, "#league-challenge-result.is-promoted")
    assert has_element?(view, "#league-challenge-result h3", "Promoted to Silver")
    refute rewards_html =~ "Proceed to Battle"
  end

  test "preview league victory marks the cleared battle and continues to the next one", %{conn: conn} do
    attacker = create_base_hero(%{league_tier: 0, league_step: 1}, create_player!(), strong_avatar())
    battle = attacker |> Game.start_league_battle!() |> Engine.auto_finish_battle!()
    assert battle.winner_id == attacker.id
    conn = init_test_session(conn, player_id: attacker.player_id)
    {:ok, view, _} = live(conn, "/battles/#{battle.id}")

    assert has_element?(view, "#league-challenge-result.is-stage-victory h3", "Victory")
    assert has_element?(view, "#league-challenge-result .league-stage-cleared", "Battle 1 cleared")
    refute has_element?(view, "#league-challenge-result .league-outcome-description")
    assert has_element?(view, "#league-challenge-step-1[data-state=complete]", "Cleared")
    assert has_element?(view, "#league-challenge-step-2[data-state=next][aria-current=step]", "Up next")
    refute has_element?(view, "#league-challenge-step-3")
    view |> element("#league-next-battle") |> render_click()
    assert_patch(view, "/battles/#{Engine.latest_battle(attacker.id).id}")

    Game.update_hero!(Game.get_hero!(attacker.id), %{league_step: 0})
    {:ok, archive, _} = live(conn, "/battles/#{battle.id}")
    refute has_element?(archive, "#league-next-battle")
    refute has_element?(archive, "#league-challenge-result [aria-current=step]")
    assert has_element?(archive, "#load-training[href='/training']")
  end

  test "preview league promotion shows rewards and returns to training", %{conn: conn} do
    attacker = create_base_hero(%{league_tier: 0, league_step: 2}, create_player!(), strong_avatar())
    battle = attacker |> Game.start_league_battle!() |> Engine.auto_finish_battle!()
    assert battle.winner_id == attacker.id
    conn = init_test_session(conn, player_id: attacker.player_id)
    {:ok, view, _} = live(conn, "/battles/#{battle.id}")

    assert has_element?(view, "#league-challenge-result h3", "Promoted to Silver")
    assert has_element?(view, "#league-challenge-result.is-promoted[data-league='1']")
    assert has_element?(view, "#league-promoted-emblem[src='/images/league/1.png']")
    assert has_element?(view, "#league-challenge-step-2[data-state=complete]")
    assert has_element?(view, "#league-promotion-rewards .league-gold-reward")
    assert has_element?(view, "#league-promotion-rewards .league-xp-reward")
    assert has_element?(view, "#load-training[href='/training']")
    refute has_element?(view, "#league-next-battle")
  end

  test "preview league defeat marks the failed step", %{conn: conn} do
    attacker = create_base_hero(%{league_tier: 1, league_step: 2, current_hp: 1}, create_player!(), weak_avatar())
    battle = attacker |> Game.start_league_battle!() |> Engine.auto_finish_battle!()
    assert battle.winner_id != attacker.id
    conn = init_test_session(conn, player_id: attacker.player_id)
    {:ok, view, _} = live(conn, "/battles/#{battle.id}")

    assert has_element?(view, "#league-challenge-result[data-result=defeat] h3", "Challenge lost")
    assert has_element?(view, "#league-challenge-step-1[data-state=complete]")
    assert has_element?(view, "#league-challenge-step-2[data-state=failed]", "Failed")
    assert has_element?(view, "#league-challenge-step-3[data-state=pending]")
    assert has_element?(view, "#load-training[href='/training']")
    refute has_element?(view, "#league-next-battle")
  end

  test "guest player ranking up after the first league challenge advances the tutorial", %{conn: conn} do
    player = create_player!(%{user_id: nil, tutorial_step: 10})

    attacker =
      create_base_hero(%{league_tier: 0, league_step: 2}, player, strong_avatar())
      |> Moba.Repo.preload(:skills)

    battle = Game.start_league_battle!(attacker)
    skill_id = attacker.skills |> List.first() |> Map.fetch!(:id)

    conn =
      conn
      |> init_test_session(player_id: attacker.player_id)

    {:ok, view, _html} = live(conn, "/battles/#{battle.id}")
    _rewards_html = play_until_finished(view, battle.id, attacker.id, skill_id, 20)

    updated_player = Game.get_player!(player.id)
    assert updated_player.tutorial_step == 11
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
        "skill_id" => "#{skill_id}",
        "item_id" => "",
        "hero_id" => "#{attacker_id}"
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
