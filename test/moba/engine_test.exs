defmodule Moba.EngineTest do
  use Moba.DataCase, async: true

  setup do
    attrs = %{pvp_points: 50, pve_tier: 1}

    base_hero = create_base_hero(attrs)
    weak_hero = create_base_hero(attrs, create_player!(attrs), weak_avatar())

    strong_hero = create_base_hero(attrs, create_player!(attrs), strong_avatar())

    alternate_hero = create_base_hero(attrs, create_player!(attrs), strong_avatar())

    %{
      weak_hero: weak_hero,
      strong_hero: strong_hero,
      base_hero: base_hero,
      alternate_hero: alternate_hero
    }
  end

  describe "battles" do
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
    test "not enough battles", %{base_hero: attacker, alternate_hero: defender} do
      updated = %{attacker | pve_current_turns: 0}
      assert {:error, _} = Engine.create_pve_battle!(%{attacker: updated, defender: defender, difficulty: "weak"})
    end

    test "battle win for attacker, level up", %{strong_hero: attacker, weak_hero: defender} do
      battle =
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "strong"})
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
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "strong"})
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

    test "battle loss for veteran attacker, gets gank back", %{weak_hero: attacker, strong_hero: defender} do
      attacker = %{attacker | pve_tier: 3}

      battle =
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "strong"})
        |> Engine.auto_finish_battle!()

      assert battle.winner.id == defender.id
      assert battle.attacker.pve_current_turns == attacker.pve_current_turns
    end
  end

  describe "league" do
    test "default case", %{strong_hero: attacker} do
      battle =
        Engine.create_league_battle!(%{attacker | league_step: 1})
        |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      assert battle.winner_id == attacker.id
      assert battle.type == "league"
      assert hero.league_attempts == attacker.league_attempts + 1
    end

    test "when invalid", %{base_hero: attacker} do
      assert {:error, _} = Engine.create_league_battle!(attacker)
    end

    test "attacker wins", %{strong_hero: attacker} do
      battle =
        Engine.create_league_battle!(%{attacker | league_step: 1})
        |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      assert battle.winner_id == attacker.id
      assert hero.league_step == 2
      assert Engine.pending_battle(attacker.id)
    end

    test "defender wins", %{weak_hero: attacker} do
      battle =
        Engine.create_league_battle!(%{attacker | league_step: 1})
        |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      assert battle.winner_id != attacker.id
      assert hero.league_step == 0
      assert hero.pve_state == "dead"
    end

    test "attacker wins and ranks up", %{strong_hero: attacker} do
      battle =
        Engine.create_league_battle!(%{attacker | league_step: 2})
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
      with_boss = Game.generate_boss!(hero)

      battle =
        Engine.create_league_battle!(%{with_boss | league_step: 1, league_tier: master_league_tier})
        |> Engine.auto_finish_battle!()

      assert battle.winner_id == with_boss.id

      with_boss = Game.get_hero!(with_boss.id)
      assert with_boss.gold == hero.gold + Moba.boss_win_bonus()
      assert with_boss.league_step == 0
      assert with_boss.league_tier == master_league_tier + 1
    end

    test "attacker loses to boss", %{weak_hero: hero} do
      master_league_tier = Moba.master_league_tier()

      with_boss =
        Game.generate_boss!(hero) |> Game.update_hero!(%{level: 25, league_step: 1, league_tier: master_league_tier})

      boss = Game.get_hero!(with_boss.boss_id)

      battle =
        Engine.create_league_battle!(with_boss)
        |> Engine.auto_finish_battle!()

      assert battle.winner_id == boss.id

      with_boss = Game.get_hero!(with_boss.id)
      assert with_boss.league_tier == master_league_tier
      assert with_boss.league_step == 1
      assert with_boss.boss_id

      battle =
        Engine.create_league_battle!(with_boss)
        |> Engine.auto_finish_battle!()

      assert battle.winner_id == boss.id

      refute battle.attacker.boss_id
      with_boss = Game.get_hero!(with_boss.id)

      refute with_boss.boss_id
    end
  end

  describe "pvp duel" do
    test "full cycle", %{strong_hero: attacker, weak_hero: defender} do
      duel = Game.create_pvp_duel!(attacker.player, defender.player)
      Game.next_duel_phase!(duel, attacker)
      duel = Game.get_duel!(duel.id)
      Game.next_duel_phase!(duel, defender)
      Engine.first_duel_battle(duel) |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      defender = Game.get_hero!(defender.id)

      assert hero.player.pvp_points == attacker.player.pvp_points

      duel = Game.get_duel!(duel.id)
      Game.next_duel_phase!(duel, defender)
      duel = Game.get_duel!(duel.id)
      Game.next_duel_phase!(duel, attacker)

      last_battle = Engine.last_duel_battle(duel) |> Engine.auto_finish_battle!()

      %{player: player} = Game.get_hero!(attacker.id)
      %{player: opponent} = Game.get_hero!(defender.id)
      duel = Game.get_duel!(duel.id)

      assert duel.rewards == last_battle.rewards
      assert duel.winner_player_id == attacker.player_id
      assert player.duel_score == %{"#{opponent.id}" => 1}
      assert opponent.duel_score == %{}

      assert player.pvp_points == attacker.player.pvp_points + 10
      assert opponent.pvp_points == defender.player.pvp_points - 10
    end
  end

  describe "core" do
    test "#begin_battle!", %{strong_hero: attacker, alternate_hero: defender} do
      battle = build_basic_battle(attacker, %{defender | bot_difficulty: "test"}) |> Engine.begin_battle!()

      assert battle.initiator == attacker
      assert length(battle.turns) == 0

      no_speed = %{attacker | speed: 0, pve_tier: 3}
      battle = build_basic_battle(no_speed, %{defender | bot_difficulty: "test"}) |> Engine.begin_battle!()

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
        create_basic_battle(attacker, %{defender | bot_difficulty: "test"})
        |> Engine.continue_battle!(%{skill: skill, item: nil})

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)

      assert previous_turn.skill_code == skill.code
      assert previous_turn.attacker.cooldowns == %{"decay" => 1}
    end

    test "#continue_battle! uses skill on cooldown", %{strong_hero: attacker, alternate_hero: defender} do
      skill = base_skill()

      battle =
        create_basic_battle(attacker, %{defender | bot_difficulty: "test"})
        |> Engine.continue_battle!(%{skill: skill, item: nil})
        |> Engine.continue_battle!(%{skill: skill, item: nil})

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)
      assert last_turn.number == 4

      assert previous_turn.skill_code == "basic_attack"
      assert previous_turn.attacker.cooldowns == %{"decay" => 0}

      battle =
        battle
        |> Engine.continue_battle!(%{skill: nil, item: nil})
        |> Engine.continue_battle!(%{skill: skill, item: nil})

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)

      assert last_turn.number == 8

      assert previous_turn.skill_code == "decay"
      assert previous_turn.attacker.cooldowns == %{"decay" => 1}
    end

    test "#continue_battle! uses item", %{strong_hero: attacker, alternate_hero: defender} do
      item = base_rare_item()
      attacker = Game.buy_item!(%{attacker | gold: 9999}, item)

      battle =
        create_basic_battle(attacker, %{defender | bot_difficulty: "test"})
        |> Engine.continue_battle!(%{skill: nil, item: item})

      assert Enum.count(battle.turns) == 2

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)

      assert previous_turn.item_code == item.code
      assert previous_turn.attacker.cooldowns == %{"tranquil_boots" => 2}
    end

    test "#auto_finish_battle!", %{strong_hero: attacker, alternate_hero: defender} do
      battle = create_basic_battle(attacker, defender) |> Engine.auto_finish_battle!()
      assert battle.finished
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
        create_basic_battle(attacker, %{defender | bot_difficulty: "test"})
        |> Engine.continue_battle!(%{skill: nil, item: nil})
        |> Engine.last_turn()

      assert last_turn.number == 2
      assert last_turn.skill_code
    end

    test "#can_use_resource?", %{strong_hero: attacker, alternate_hero: defender} do
      skill = base_skill()
      battle = create_basic_battle(attacker, %{defender | bot_difficulty: "test"})
      assert Engine.build_turn(battle) |> Engine.can_use_resource?(skill)
      battle = Engine.continue_battle!(battle, %{skill: skill, item: nil})
      refute Engine.build_turn(battle) |> Engine.can_use_resource?(skill)
    end
  end

  describe "simulations" do
    test "skill and item effects dont break" do
      avatars = Game.list_avatars()

      skills =
        Game.Query.SkillQuery.normals()
        |> Game.Query.SkillQuery.canon()
        |> Game.Query.SkillQuery.with_level(1)
        |> Repo.all()

      items = Game.shop_list()

      Enum.reduce(avatars, [], fn a1, acc ->
        # Logger.info("\n\n-----------Battle ##{a1.id}: #{a1.ultimate_code}\n\n")
        a2 = avatars |> Enum.shuffle() |> List.first()

        a1 = %{a1 | atk: 1, total_mp: 200}
        a2 = %{a2 | atk: 1, total_mp: 200}

        acc = if Enum.count(acc) >= Enum.count(skills), do: [], else: acc
        s1 = Enum.shuffle(skills) |> Enum.reject(fn skill -> Enum.member?(acc, skill) end) |> Enum.take(3)
        acc = acc ++ s1

        acc = if Enum.count(acc) >= Enum.count(skills), do: [], else: acc
        s2 = Enum.shuffle(skills) |> Enum.reject(fn skill -> Enum.member?(acc, skill) end) |> Enum.take(3)
        acc = acc ++ s2

        attacker = Game.create_hero!(%{name: "attacker"}, nil, a1, s1) |> equip_random_items(items)
        defender = Game.create_hero!(%{name: "defender"}, nil, a2, s2) |> equip_random_items(items)
        assert create_basic_battle(attacker, defender) |> Engine.auto_finish_battle!()

        acc
      end)
    end
  end
end
