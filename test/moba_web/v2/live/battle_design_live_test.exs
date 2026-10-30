defmodule MobaWeb.V2.BattleDesignLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "preview keeps usable skills, items and basic attacks keyboard selectable", %{conn: conn} do
    attacker = create_base_hero(%{gold: 10000}) |> Game.buy_item!(Game.get_item_by_code!("dagon"))
    defender = create_base_hero()
    battle = create_basic_battle(attacker, defender)
    conn = init_test_session(conn, player_id: attacker.player_id)
    {:ok, view, _} = live(conn, "/battles/#{battle.id}")

    refute has_element?(view, "#battle-heading")
    assert has_element?(view, "#battle-bar [id^='active-skill-'][role=button][tabindex='0']")
    assert has_element?(view, "#battle-bar [id^='attacker-item-'][role=button][aria-pressed=false]")
    assert has_element?(view, "#pick-basic-attack[role=button][tabindex='0']")
    assert has_element?(view, "#attack-button[data-hero='#{attacker.id}']")
    refute has_element?(view, "#battle-bar button.game-stat")
    refute has_element?(view, "#battle-bar .battle-action-label")

    view |> element("#pick-basic-attack") |> render_click()
    assert has_element?(view, "#pick-basic-attack[aria-pressed=true]")
    assert has_element?(view, "#active-skill-name", "Basic Attack")

    render_click(view, "next-turn", %{"skill_id" => "", "item_id" => "", "hero_id" => "#{attacker.id}"})
    assert has_element?(view, "#turn-1 .combat-turn-heading h3", "#{attacker.name} used Basic Attack")
    last_turn = Engine.get_battle!(battle.id).turns |> List.last()

    assert has_element?(
             view,
             "#scroll-to-turn[phx-hook=BattleTurnScroll][phx-target-element='#turn-1'][data-last-turn='#{last_turn.number}']"
           )

    assert has_element?(view, "#turn-1 .combat-unit", attacker.name)
    assert has_element?(view, "#turn-1 .combat-unit", defender.name)
  end

  test "defender controls use the same active layout and submit a turn", %{conn: conn} do
    attacker =
      create_base_hero(%{name: "Attacker"})
      |> Ecto.Changeset.change(%{speed: 0, pve_tier: 1})
      |> Moba.Repo.update!()

    defender =
      create_base_hero(%{name: "Defender"})
      |> Ecto.Changeset.change(%{speed: 200})
      |> Moba.Repo.update!()

    battle = create_basic_battle(attacker, defender)
    conn = init_test_session(conn, player_id: defender.player_id)
    {:ok, view, _} = live(conn, "/battles/#{battle.id}")

    assert has_element?(
             view,
             ".battle-action-side:not(.battle-passive-side) #attack-button[data-hero='#{defender.id}']"
           )

    refute has_element?(view, ".battle-action-side.d-none #attack-button")
    render_click(view, "next-turn", %{"skill_id" => "", "item_id" => "", "hero_id" => "#{defender.id}"})
    assert has_element?(view, "#turn-1 .combat-turn-actor", defender.name)
  end

  test "finished replay retains every turn, effect detail and reward navigation", %{conn: conn} do
    hero = create_base_hero(%{}, create_player!(), strong_avatar())
    Game.generate_targets!(hero)
    target = hero |> Game.list_targets() |> List.first() |> then(&Game.get_target!(&1.id))
    battle = target |> Game.start_pve_battle!() |> Engine.auto_finish_battle!()
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/battles/#{battle.id}")

    for turn <- battle.turns do
      assert has_element?(view, "#turn-#{turn.number}[aria-labelledby='turn-title-#{turn.number}']")

      assert has_element?(
               view,
               "#turn-#{turn.number} .combat-unit .health strong",
               "#{max(turn.attacker.current_hp, 0)}"
             )

      assert has_element?(view, "#turn-effects-#{turn.number}")
    end

    assert has_element?(view, "h2#battle-initiated", "Training battle initiated by #{battle.initiator.name}")
    refute has_element?(view, "#battle-heading")
    assert has_element?(view, "#battle-outcome[data-result=victory]")
    assert has_element?(view, "#battle-experience")
    assert has_element?(view, "#load-training[href='/training']")
    assert has_element?(view, "#load-battles[href='/battles']")
    assert has_element?(view, "#battle-over-training[href='/training']")
    assert has_element?(view, "#share-battle")
    refute has_element?(view, "#attack-button")
  end

  test "older replay resources follow previous turns", %{conn: conn} do
    hero = create_base_hero()
    battle = create_basic_battle(hero, create_base_hero()) |> Engine.auto_finish_battle!()

    Moba.Repo.query!(
      "UPDATE turns SET attacker = attacker - 'starting_hp' - 'starting_mp', defender = defender - 'starting_hp' - 'starting_mp' WHERE battle_id = $1",
      [battle.id]
    )

    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, modern, _} = live(conn, "/battles/#{battle.id}")

    for {turn, previous} <- Enum.zip(battle.turns, [nil | battle.turns]), battler <- [turn.attacker, turn.defender] do
      before =
        if previous do
          if previous.attacker.hero_id == battler.hero_id, do: previous.attacker, else: previous.defender
        end

      hp = min(max(battler.current_hp, 0), battler.total_hp)
      before_hp = min(max((before && before.current_hp) || battler.total_hp, 0), battler.total_hp)

      assert has_element?(
               modern,
               "#turn-#{turn.number} .health[data-before='#{before_hp}'][data-current='#{hp}'][data-change='#{hp - before_hp}']"
             )
    end
  end

  test "older season replays recover the winner's carried-over resources", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    hero = create_base_hero(%{}, player) |> Game.update_hero!(%{total_hp: 2000, total_mp: 0, atk: 50, armor: 0})
    enemy = create_base_hero(%{}, opponent) |> Game.update_hero!(%{total_hp: 500, total_mp: 0, atk: 100, armor: 0})

    match =
      Moba.Game.Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [hero.id],
        opponent_picks: [enemy.id],
        generated_picks: [],
        type: "manual"
      })

    attrs = %{attacker: hero, attacker_player: player, defender: enemy, defender_player: opponent, match: match}
    previous = Engine.create_match_battle!(attrs)
    assert previous.winner_id == hero.id
    last = List.last(previous.turns)
    winner = if last.attacker.hero_id == hero.id, do: last.attacker, else: last.defender
    hp = winner.current_hp + winner.total_hp * 0.2
    mp = winner.current_mp + winner.total_mp * 0.2
    battle = Engine.create_match_battle!(%{attrs | attacker: Map.merge(hero, %{initial_hp: hp, initial_mp: mp})})

    Moba.Repo.query!(
      "UPDATE turns SET attacker = attacker - 'starting_hp' - 'starting_mp', defender = defender - 'starting_hp' - 'starting_mp' WHERE battle_id = $1",
      [battle.id]
    )

    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/battles/#{battle.id}")
    assert has_element?(view, "h2#battle-initiated", "Season match initiated by")
    assert has_element?(view, "#battle-competitive-result[data-result=victory]")
    assert has_element?(view, "#load-battles[href='/matches/#{match.id}']", "Back to match")
    assert has_element?(view, "#turn-1 .health[data-before='#{min(round(hp), winner.total_hp)}']")
    assert has_element?(view, "#turn-1 .energy[data-before='0']")
  end

  test "duel results follow the player controlling the hero in each round", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    hero = Game.create_hero!(%{name: "Champion"}, player, strong_avatar(), base_skills())
    enemy = Game.create_hero!(%{name: "Challenger"}, opponent, weak_avatar(), base_skills())
    duel = Game.create_duel!(player, opponent, false)
    Game.continue_duel!(duel, hero)
    Game.continue_duel!(Game.get_duel!(duel.id), enemy)
    battle = duel |> Map.get(:id) |> Game.get_duel!() |> Engine.first_duel_battle() |> Engine.auto_finish_battle!()

    {:ok, winner, _} = live(init_test_session(conn, player_id: player.id), "/battles/#{battle.id}")

    assert has_element?(
             winner,
             "#battle-competitive-result.is-duel-result[data-stage=round][data-result=victory]",
             "Champion wins"
           )

    assert has_element?(winner, ".battle-result-context", "Battle 1 of 2")
    refute has_element?(winner, ".duel-victory-seal")
    assert has_element?(winner, "#load-battles[href='/arena/#{duel.id}']", "Continue duel")
    {:ok, loser, _} = live(init_test_session(conn, player_id: opponent.id), "/battles/#{battle.id}")
    assert has_element?(loser, "#battle-competitive-result[data-result=defeat]")

    Game.continue_duel!(Game.get_duel!(duel.id), hero)
    Game.continue_duel!(Game.get_duel!(duel.id), enemy)
    rematch = duel.id |> Game.get_duel!() |> Engine.last_duel_battle() |> Engine.auto_finish_battle!()
    {:ok, reversed, _} = live(init_test_session(conn, player_id: opponent.id), "/battles/#{rematch.id}")

    assert has_element?(
             reversed,
             "#battle-competitive-result[data-stage=final][data-result=draw] #battle-result-title",
             "Duel drawn"
           )

    refute has_element?(reversed, ".duel-victory-seal")

    spectator = create_player!()
    {:ok, replay, _} = live(init_test_session(conn, player_id: spectator.id), "/battles/#{battle.id}")
    assert has_element?(replay, "#battle-competitive-result[data-result=complete]")
  end

  test "winning the final duel battle celebrates the overall win immediately", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    hero = Game.create_hero!(%{name: "Champion"}, player, strong_avatar(), base_skills())

    enemy =
      Game.create_hero!(%{name: "Challenger"}, opponent, weak_avatar(), base_skills())
      |> Ecto.Changeset.change(%{pve_tier: 1, speed: 0})
      |> Moba.Repo.update!()

    duel = Game.create_duel!(player, opponent, false)
    Game.continue_duel!(duel, hero)
    Game.continue_duel!(Game.get_duel!(duel.id), enemy)
    first = duel.id |> Game.get_duel!() |> Engine.first_duel_battle() |> Engine.auto_finish_battle!()
    assert first.winner_player_id == player.id
    Game.continue_duel!(Game.get_duel!(duel.id), enemy)
    Game.continue_duel!(Game.get_duel!(duel.id), hero)
    final = duel.id |> Game.get_duel!() |> Engine.last_duel_battle()
    refute final.finished
    assert final.initiator_player_id == player.id
    session = init_test_session(conn, player_id: player.id)
    {:ok, view, _} = live(session, "/battles/#{final.id}")

    render_click(view, "next-turn", %{"skill_id" => "", "item_id" => "", "hero_id" => "#{hero.id}"})

    assert has_element?(view, "#battle-competitive-result.is-duel-finale[data-stage=final][data-result=victory]")
    assert has_element?(view, "#battle-result-title", "Duel victory")
    assert has_element?(view, ".duel-victory-seal")
    assert has_element?(view, ".duel-result-points[data-gain=true] strong", "+5")
    assert has_element?(view, "#load-battles[href='/arena/#{duel.id}']", "View duel result")
    assert Game.get_duel!(duel.id).winner_player_id == player.id

    {:ok, loser, _} = live(init_test_session(conn, player_id: opponent.id), "/battles/#{final.id}")
    assert has_element?(loser, "#battle-competitive-result[data-stage=final][data-result=defeat]", "Duel defeat")
    refute has_element?(loser, ".duel-victory-seal")

    spectator = create_player!()
    {:ok, replay, _} = live(init_test_session(conn, player_id: spectator.id), "/battles/#{final.id}")
    assert has_element?(replay, "#battle-competitive-result[data-result=complete]", "Duel complete")
    refute has_element?(replay, ".duel-victory-seal")

    {:ok, archive, _} = live(session, "/battles/#{first.id}")
    assert has_element?(archive, "#battle-competitive-result[data-stage=round][data-result=victory]")
    refute has_element?(archive, ".duel-victory-seal, .duel-result-points")
  end

  test "opening battle states guide either player and keep spectators informed", %{conn: conn} do
    attacker = create_base_hero()
    defender = create_base_hero()
    battle = create_basic_battle(attacker, defender)
    first = if battle.initiator_id == attacker.id, do: attacker, else: defender
    second = if battle.initiator_id == attacker.id, do: defender, else: attacker

    {:ok, active, _} = live(init_test_session(conn, player_id: first.player_id), "/battles/#{battle.id}")
    assert has_element?(active, "#battle-ready[data-state=ready]", "Make your first move")
    assert has_element?(active, "#attack-button[data-hero='#{first.id}']")
    {:ok, waiting, _} = live(init_test_session(conn, player_id: second.player_id), "/battles/#{battle.id}")
    assert has_element?(waiting, "#battle-ready[data-state=waiting]", "Waiting for #{first.name}")
    refute has_element?(waiting, "#attack-button")
    spectator = create_player!()
    {:ok, watching, _} = live(init_test_session(conn, player_id: spectator.id), "/battles/#{battle.id}")
    assert has_element?(watching, "#battle-ready[data-state=waiting]", "The battle will appear here")
    refute has_element?(watching, "#attack-button")
  end

  test "a drawn competitive replay does not announce a winner", %{conn: conn} do
    hero = create_base_hero()
    battle = create_basic_battle(hero, create_base_hero()) |> Engine.auto_finish_battle!()
    Moba.Repo.update!(Ecto.Changeset.change(battle, type: "match", winner_id: nil))
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/battles/#{battle.id}")
    assert has_element?(view, "#battle-competitive-result[data-result=draw] #battle-result-title", "Draw")
    assert has_element?(view, "#battle-competitive-result", "Both heroes survived")
    refute has_element?(view, "#battle-competitive-result .battle-result-identity > img")
  end
end
