defmodule Moba.EngineTest do
  use Moba.DataCase, async: true

  setup tags do
    attrs = %{pvp_points: 50, pve_tier: 1}

    factories = %{
      base_hero: fn -> create_combat_hero(attrs) end,
      weak_hero: fn -> create_combat_hero(attrs, create_player!(attrs), weak_avatar()) end,
      strong_hero: fn -> create_combat_hero(attrs, create_player!(attrs), strong_avatar()) end,
      alternate_hero: fn -> create_combat_hero(attrs, create_player!(attrs), strong_avatar()) end
    }

    Map.new(tags.heroes, &{&1, Map.fetch!(factories, &1).()})
  end

  describe "battles" do
    @describetag heroes: [:strong_hero, :alternate_hero]
    test "optional battle lookup loads existing battles and returns nil for missing or invalid IDs", %{
      strong_hero: attacker,
      alternate_hero: defender
    } do
      battle = create_basic_battle(attacker, defender)
      assert Engine.get_battle("#{battle.id}") == Engine.get_battle!(battle.id)

      Repo.delete!(battle)
      assert Engine.get_battle(battle.id) == nil

      for id <- [nil, "invalid", "1invalid", "", 0, -1, "9223372036854775808"] do
        assert Engine.get_battle(id) == nil
      end

      assert_raise Ecto.NoResultsError, fn -> Engine.get_battle!(battle.id) end
    end

    test "#update_battle!", %{strong_hero: attacker, alternate_hero: defender} do
      battle = create_basic_battle(attacker, defender) |> Engine.update_battle!(%{difficulty: "test"})
      assert battle.difficulty == "test"
    end

    test "#generate_attacker_snapshot", %{strong_hero: attacker, alternate_hero: defender} do
      battle = create_basic_battle(attacker, defender)
      battle = Engine.generate_attacker_snapshot!({battle, attacker})

      assert battle.attacker_snapshot.level == attacker.level
      refute battle.attacker_snapshot.leveled_up
    end

    test "#generate_defender_snapshot", %{strong_hero: attacker, alternate_hero: defender} do
      battle = create_basic_battle(attacker, defender)
      battle = Engine.generate_defender_snapshot!({battle, attacker, defender})

      assert battle.defender_snapshot.level == attacker.level
      refute battle.defender_snapshot.leveled_up
    end
  end

  describe "pve" do
    @describetag heroes: [:strong_hero, :weak_hero]
    @tag heroes: [:base_hero, :alternate_hero]
    test "not enough battles", %{base_hero: attacker, alternate_hero: defender} do
      updated = Game.update_hero!(attacker, %{pve_current_turns: 0})
      assert {:error, _} = Game.start_pve_battle!(%{attacker: updated, defender: defender, difficulty: "weak"})
    end

    test "battle win for attacker, level up", %{strong_hero: attacker, weak_hero: defender} do
      battle =
        Game.start_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "strong"})
        |> Engine.auto_finish_battle!()

      assert battle.winner.id == attacker.id

      battle = Engine.get_battle!(battle.id)
      assert battle.winner.id == attacker.id

      rewards = battle.rewards
      assert rewards.total_xp == 600

      reloaded_attacker = Game.get_hero!(attacker.id)
      reloaded_defender = Game.get_hero!(defender.id)

      assert reloaded_attacker.total_xp_farm == attacker.total_xp_farm + 600
      assert reloaded_attacker.level > attacker.level
      assert reloaded_attacker.wins == 1

      assert reloaded_attacker.pve_current_turns == attacker.pve_current_turns - 1
      assert reloaded_defender.pve_current_turns == defender.pve_current_turns

      assert defender.experience == 0
      refute attacker.pve_state == "dead"
    end

    test "battle loss for attacker, no xp", %{weak_hero: attacker, strong_hero: defender} do
      battle =
        Game.start_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "strong"})
        |> Engine.auto_finish_battle!()

      assert battle.winner.id == defender.id

      attacker = Game.get_hero!(attacker.id)
      defender = Game.get_hero!(defender.id)

      assert attacker.experience == 0
      assert attacker.level == 1
      assert attacker.losses == 1
      assert attacker.pve_state == "dead"

      assert defender.experience == 0
    end

    test "battle loss for attacker, gets gank back", %{weak_hero: attacker, strong_hero: defender} do
      battle =
        Game.start_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "strong"})
        |> Engine.auto_finish_battle!()

      reloaded_attacker = Game.get_hero!(attacker.id)

      assert battle.winner.id == defender.id
      assert reloaded_attacker.pve_current_turns == attacker.pve_current_turns
    end
  end

  describe "league" do
    @describetag heroes: [:strong_hero]
    test "default case", %{strong_hero: attacker} do
      battle =
        Game.start_league_battle!(attacker)
        |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      assert battle.winner_id == attacker.id
      assert battle.type == "league"
      assert hero.league_attempts == attacker.league_attempts + 1
    end

    test "attacker wins", %{strong_hero: attacker} do
      battle =
        Game.start_league_battle!(attacker)
        |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      assert battle.winner_id == attacker.id
      assert hero.league_step == 2
      assert Engine.pending_battle(attacker.id)
    end

    @tag heroes: [:weak_hero]
    test "defender wins", %{weak_hero: attacker} do
      battle =
        Game.start_league_battle!(attacker)
        |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      assert battle.winner_id != attacker.id
      assert hero.league_step == 0
      assert hero.pve_state == "dead"
    end

    test "attacker wins and ranks up", %{strong_hero: attacker} do
      battle =
        Game.start_league_battle!(Game.update_hero!(attacker, %{league_step: 2}))
        |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      assert battle.winner_id == attacker.id
      assert hero.league_step == 0
      assert hero.league_tier == attacker.league_tier + 1
      assert hero.league_successes == attacker.league_successes + 1

      assert hero.gold == attacker.gold + Moba.league_win_bonus()
      assert hero.total_gold_farm == attacker.total_gold_farm + Moba.league_win_bonus()
      assert hero.total_xp_farm == attacker.total_xp_farm + Moba.league_win_bonus()
    end

    test "attacker beats boss and ranks up", %{strong_hero: hero} do
      master_league_tier = Moba.master_league_tier()

      with_boss =
        hero
        |> Game.update_hero!(%{league_step: 1, league_tier: master_league_tier, pve_tier: 2, pve_total_turns: 0})
        |> Game.generate_boss!()

      battle =
        Game.start_league_battle!(with_boss)
        |> Engine.auto_finish_battle!()

      assert battle.winner_id == with_boss.id

      with_boss = Game.get_hero!(with_boss.id)
      assert with_boss.finished_at
      assert with_boss.level == Moba.max_hero_level()
      assert with_boss.gold == 32_000
      assert with_boss.total_gold_farm == hero.total_gold_farm + Moba.boss_win_bonus()
      assert with_boss.total_xp_farm == hero.total_xp_farm + Moba.boss_win_bonus()
      assert with_boss.league_step == 0
      assert with_boss.league_tier == master_league_tier + 1
    end

    @tag heroes: [:weak_hero]
    test "attacker loses to boss", %{weak_hero: hero} do
      master_league_tier = Moba.master_league_tier()

      with_boss =
        Game.generate_boss!(hero) |> Game.update_hero!(%{level: 25, league_step: 1, league_tier: master_league_tier})

      boss = Game.get_hero!(with_boss.boss_id)

      battle =
        Game.start_league_battle!(with_boss)
        |> Engine.auto_finish_battle!()

      assert battle.winner_id == boss.id

      with_boss = Game.get_hero!(with_boss.id)
      assert with_boss.league_tier == master_league_tier
      assert with_boss.league_step == 1
      assert with_boss.boss_id

      with_boss =
        with_boss
        |> Game.update_hero!(%{gold: Game.buyback_price(with_boss)})
        |> Game.buyback!()

      battle =
        Game.start_league_battle!(with_boss)
        |> Engine.auto_finish_battle!()

      assert battle.winner_id == boss.id

      refute battle.attacker.boss_id
      with_boss = Game.get_hero!(with_boss.id)

      refute with_boss.boss_id
    end
  end

  describe "pvp duel" do
    @describetag heroes: [:strong_hero, :weak_hero]
    test "full cycle", %{strong_hero: attacker, weak_hero: defender} do
      duel = Game.create_duel!(attacker.player, defender.player)
      Game.continue_duel!(duel, attacker)
      duel = Game.get_duel!(duel.id)
      Game.continue_duel!(duel, defender)
      Engine.first_duel_battle(duel) |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      defender = Game.get_hero!(defender.id)

      assert hero.player.pvp_points == attacker.player.pvp_points

      duel = Game.get_duel!(duel.id)
      Game.continue_duel!(duel, defender)
      duel = Game.get_duel!(duel.id)
      Game.continue_duel!(duel, attacker)

      Engine.last_duel_battle(duel) |> Engine.auto_finish_battle!()

      %{player: player} = Game.get_hero!(attacker.id)
      %{player: opponent} = Game.get_hero!(defender.id)
      duel = Game.get_duel!(duel.id)

      assert duel.rewards.attacker_pvp_points == 5
      assert duel.rewards.defender_pvp_points == -5
      assert duel.winner_player_id == attacker.player_id
      assert player.duel_score == %{"#{opponent.id}" => 1}
      assert opponent.duel_score == %{}

      assert player.pvp_points == attacker.player.pvp_points + 5
      assert opponent.pvp_points == defender.player.pvp_points - 5
    end
  end

  describe "same hero battle" do
    @describetag heroes: [:strong_hero, :weak_hero]
    test "attacker wins", %{strong_hero: strong, weak_hero: weak} do
      match = Game.Matches.create!(%{type: "manual", player_id: strong.player_id, opponent_id: weak.player_id})

      attacker =
        weak
        |> Map.put(:initial_hp, 100_000)
        |> Map.put(:total_hp, 100_000)
        |> Map.put(:atk, 1000)
        |> Map.put(:skill_order, [""])

      battle =
        Engine.create_match_battle!(%{
          attacker: attacker,
          attacker_player: strong.player,
          defender: weak,
          defender_player: weak.player,
          match: match
        })

      battle = Engine.auto_finish_battle!(battle)

      assert battle.winner_player_id == strong.player_id
    end

    test "defender wins", %{strong_hero: strong, weak_hero: weak} do
      match = Game.Matches.create!(%{type: "manual", player_id: strong.player_id, opponent_id: weak.player_id})
      attacker = Map.put(weak, :initial_hp, 1)

      battle =
        Engine.create_match_battle!(%{
          attacker: attacker,
          attacker_player: strong.player,
          defender: weak,
          defender_player: weak.player,
          match: match
        })

      battle = Engine.auto_finish_battle!(battle)

      assert battle.winner_player_id == weak.player_id
    end
  end

  describe "core" do
    @describetag heroes: [:strong_hero, :alternate_hero]
    test "#begin_battle!", %{strong_hero: attacker, alternate_hero: defender} do
      battle =
        build_basic_battle(attacker, Game.update_hero!(defender, %{bot_difficulty: "test"})) |> Engine.begin_battle!()

      assert battle.initiator == attacker
      assert length(battle.turns) == 0

      no_speed = %{attacker | speed: 0, pve_tier: 3}

      battle =
        build_basic_battle(no_speed, Game.update_hero!(defender, %{bot_difficulty: "test"})) |> Engine.begin_battle!()

      assert battle.initiator.id == defender.id
      assert length(battle.turns) == 1
    end

    test "#continue_battle! default case", %{strong_hero: attacker, alternate_hero: defender} do
      battle = create_basic_battle(attacker, defender) |> Engine.continue_battle!(%{skill: nil, item: nil})
      assert length(battle.turns) > 0
    end

    test "#continue_battle! uses skill", %{strong_hero: attacker, alternate_hero: defender} do
      skill = base_skill()

      battle =
        create_basic_battle(attacker, Game.update_hero!(defender, %{bot_difficulty: "test"}))
        |> Engine.continue_battle!(%{skill: skill, item: nil})

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)

      assert previous_turn.skill_code == skill.code
      assert previous_turn.attacker.cooldowns == %{"decay" => 1}
    end

    test "#continue_battle! uses skill on cooldown", %{strong_hero: attacker, alternate_hero: defender} do
      skill = base_skill()

      battle =
        create_basic_battle(attacker, Game.update_hero!(defender, %{bot_difficulty: "test"}))
        |> Engine.continue_battle!(%{skill: skill, item: nil})
        |> Engine.continue_battle!(%{skill: skill, item: nil})

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)
      assert last_turn.number == 4

      assert previous_turn.skill_code == "basic_attack"
      assert previous_turn.attacker.cooldowns["decay"] == 0

      battle =
        battle
        |> Engine.continue_battle!(%{skill: nil, item: nil})
        |> Engine.continue_battle!(%{skill: skill, item: nil})

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)

      assert last_turn.number == 8

      assert previous_turn.skill_code == "decay"
      assert previous_turn.attacker.cooldowns["decay"] == 1
    end

    test "#continue_battle! uses item", %{strong_hero: attacker, alternate_hero: defender} do
      item = base_rare_item()
      attacker = Game.buy_item!(%{attacker | gold: 9999}, item)

      battle =
        create_basic_battle(attacker, Game.update_hero!(defender, %{bot_difficulty: "test"}))
        |> Engine.continue_battle!(%{skill: nil, item: item})

      assert Enum.count(battle.turns) == 2

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)

      assert previous_turn.item_code == item.code
      assert previous_turn.attacker.cooldowns == %{"tranquil_boots" => 2}
    end

    @tag heroes: [:strong_hero, :weak_hero]
    test "#auto_finish_battle!", %{strong_hero: attacker, weak_hero: defender} do
      battle = create_basic_battle(attacker, defender) |> Engine.auto_finish_battle!()
      assert battle.finished
      assert battle.winner_id == attacker.id
      assert Engine.get_battle!(battle.id).finished
      assert length(battle.turns) < 10
    end

    test "#build_turn", %{strong_hero: attacker, alternate_hero: defender} do
      battle = create_basic_battle(attacker, defender)
      turn = Engine.build_turn(battle)

      assert turn.number == 1
      assert turn.attacker.hero_id == attacker.id
      assert turn.defender.hero_id == defender.id
    end

    test "#last_turn", %{strong_hero: attacker, alternate_hero: defender} do
      last_turn =
        create_basic_battle(attacker, Game.update_hero!(defender, %{bot_difficulty: "test"}))
        |> Engine.continue_battle!(%{skill: nil, item: nil})
        |> Map.get(:turns)
        |> List.last()

      assert last_turn.number == 2
      assert last_turn.skill_code
    end

    test "#can_use_resource?", %{strong_hero: attacker, alternate_hero: defender} do
      skill = base_skill()
      battle = create_basic_battle(attacker, Game.update_hero!(defender, %{bot_difficulty: "test"}))
      assert Engine.build_turn(battle) |> Engine.can_use_resource?(skill)
      battle = Engine.continue_battle!(battle, %{skill: skill, item: nil})
      refute Engine.build_turn(battle) |> Engine.can_use_resource?(skill)
    end
  end

  describe "simulations" do
    @describetag heroes: []
    test "every avatar completes a short persisted battle with skills and items" do
      avatars = Game.list_avatars()
      skills = base_skills()
      items = [base_item(), Game.get_item_by_code!("dagon")]

      attrs =
        Map.merge(Game.item_attributes(items), %{
          name: "Fighter",
          total_hp: 80,
          total_mp: 200,
          atk: 200,
          armor: 0,
          power: 0
        })

      # Broad combinations and proc outcomes belong to the pure combat matrices.
      # This test covers real loadout snapshots, turn persistence and completion for every avatar.
      for {avatar, index} <- Enum.with_index(avatars) do
        :rand.seed(:exsss, {1, 2, index + 1})
        opponent = Enum.at(avatars, rem(index + 1, length(avatars)))
        attacker = Game.Heroes.create!(attrs, nil, avatar, skills, items) |> then(&Game.get_hero!(&1.id))
        defender = Game.Heroes.create!(attrs, nil, opponent, skills, items) |> then(&Game.get_hero!(&1.id))
        battle = create_basic_battle(attacker, defender) |> Engine.auto_finish_battle!()
        assert battle.finished
        assert battle.turns != []
        assert length(battle.turns) < 20
        assert Engine.get_battle!(battle.id).finished
        assert Enum.any?(battle.turns, & &1.skill_code)
        assert Enum.any?(battle.turns, & &1.item_code)
      end
    end
  end
end
