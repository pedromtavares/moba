defmodule Moba.EngineTest do
  use Moba.DataCase, async: true

  setup do
    attrs = %{pvp_points: 50, season_points: 50}

    base_hero = create_base_hero(attrs)
    weak_hero = create_base_hero(attrs, create_user(attrs), weak_avatar())

    strong_hero = create_base_hero(attrs, create_user(attrs), strong_avatar())

    alternate_hero = create_base_hero(attrs, create_user(attrs), strong_avatar())

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

    test "#read_battle!", %{strong_hero: attacker, alternate_hero: defender} do
      battle =
        Engine.create_pvp_battle!(%{attacker: attacker, defender: defender})
        |> Engine.auto_finish_battle!()

      assert battle.unread_id == defender.id
      refute Engine.read_battle!(battle) |> Map.get(:unread_id)
    end

    test "#unread_battles_count", %{strong_hero: attacker, alternate_hero: defender} do
      assert Engine.unread_battles_count(defender) == 0

      Engine.create_pvp_battle!(%{attacker: attacker, defender: defender})
      |> Engine.auto_finish_battle!()

      assert Engine.unread_battles_count(defender) == 1
    end

    test "#read_all_battles", %{strong_hero: attacker, alternate_hero: defender} do
      Engine.create_pvp_battle!(%{attacker: attacker, defender: defender})
      |> Engine.auto_finish_battle!()

      assert Engine.unread_battles_count(defender) == 1

      Engine.read_all_battles()

      assert Engine.unread_battles_count(defender) == 0
    end

    test "#read_all_battles_for", %{strong_hero: attacker, alternate_hero: defender} do
      Engine.create_pvp_battle!(%{attacker: attacker, defender: defender})
      |> Engine.auto_finish_battle!()

      assert Engine.unread_battles_count(defender) == 1

      Engine.read_all_battles_for(defender)

      assert Engine.unread_battles_count(defender) == 0
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

    test "battle ties and attacker gains xp", %{strong_hero: attacker, alternate_hero: defender} do
      battle =
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "weak"})
        |> Engine.auto_finish_battle!()

      assert battle.type == "pve"

      rewards = battle.rewards
      assert rewards.battle_xp == 400
      assert rewards.win_xp == 0
      assert rewards.total_xp == 400

      reloaded_attacker = Game.get_hero!(attacker.id)
      reloaded_defender = Game.get_hero!(defender.id)

      assert reloaded_attacker.experience > attacker.experience
      assert reloaded_defender.experience == defender.experience
      assert reloaded_attacker.ties == 1

      assert reloaded_attacker.pve_current_turns == attacker.pve_current_turns - 1
      assert reloaded_defender.pve_current_turns == defender.pve_current_turns

      assert reloaded_attacker.level == 1
      assert reloaded_attacker.gold == attacker.gold + 400
      assert reloaded_attacker.total_gold_farm == attacker.total_gold_farm + 400
      assert reloaded_attacker.total_xp_farm == attacker.total_xp_farm + 400
    end

    test "battle win for attacker, level up", %{strong_hero: attacker, weak_hero: defender} do
      battle =
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "strong"})
        |> Engine.auto_finish_battle!()

      assert battle.winner.id == attacker.id

      battle = Engine.get_battle!(battle.id)
      assert battle.winner.id == attacker.id

      rewards = battle.rewards
      assert rewards.battle_xp == 500
      assert rewards.win_xp == 100
      assert rewards.total_xp == 600

      updated_attacker = Game.get_hero!(attacker.id)
      defender = Game.get_hero!(defender.id)

      assert updated_attacker.total_xp_farm == attacker.total_xp_farm + 600
      assert updated_attacker.level > attacker.level
      assert updated_attacker.wins == 1

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

  describe "pvp" do
    test "valid first battle, invalid second battle", %{strong_hero: attacker, alternate_hero: defender} do
      assert Engine.can_pvp?(attacker, defender)

      battle =
        Engine.create_pvp_battle!(%{attacker: attacker, defender: defender})
        |> Engine.auto_finish_battle!()

      assert battle.type == "pvp"
      assert battle.unread_id == defender.id

      assert battle.attacker_snapshot.level == attacker.level
      assert battle.defender_snapshot.level == defender.level

      hero = Game.get_hero!(attacker.id)
      assert {:error, _} = Engine.create_pvp_battle!(%{attacker: hero, defender: defender})
      refute Engine.can_pvp?(hero, defender)
    end

    test "attacker wins", %{strong_hero: attacker, weak_hero: defender} do
      Engine.create_pvp_battle!(%{attacker: %{attacker | league_tier: 6}, defender: %{defender | league_tier: 6}})
      |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)

      assert hero.pvp_points == attacker.pvp_points + 9
      assert hero.pvp_wins == attacker.pvp_wins + 1
    end

    test "defender wins", %{strong_hero: defender, weak_hero: attacker} do
      Engine.create_pvp_battle!(%{attacker: %{attacker | league_tier: 6}, defender: %{defender | league_tier: 6}})
      |> Engine.auto_finish_battle!()

      updated_attacker = Game.get_hero!(attacker.id)
      updated_defender = Game.get_hero!(defender.id)

      assert updated_attacker.pvp_points == attacker.pvp_points - 9
      assert updated_defender.pvp_points == defender.pvp_points + 2
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

  describe "duel" do
    test "full cycle", %{strong_hero: attacker, weak_hero: defender} do
      duel = Game.create_duel!(attacker.user, defender.user)
      Game.next_duel_phase!(duel, attacker.id)
      duel = Game.get_duel!(duel.id)
      Game.next_duel_phase!(duel, defender.id)
      Engine.first_duel_battle(duel) |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      defender = Game.get_hero!(defender.id)

      assert hero.user.season_points == attacker.user.season_points

      duel = Game.get_duel!(duel.id)
      Game.next_duel_phase!(duel, defender.id)
      duel = Game.get_duel!(duel.id)
      Game.next_duel_phase!(duel, attacker.id)

      last_battle = Engine.last_duel_battle(duel) |> Engine.auto_finish_battle!()

      %{user: user} = Game.get_hero!(attacker.id)
      %{user: opponent} = Game.get_hero!(defender.id)
      duel = Game.get_duel!(duel.id)

      assert duel.rewards == last_battle.rewards
      assert duel.winner_id == attacker.user_id
      assert user.duel_count == attacker.user.duel_count + 1
      assert opponent.duel_count == defender.user.duel_count + 1
      assert user.duel_wins == attacker.user.duel_wins + 1
      assert user.duel_score == %{"#{opponent.id}" => 1}
      assert opponent.duel_score == %{}

      assert user.season_points == attacker.user.season_points + 18
      assert opponent.season_points == defender.user.season_points - 4
    end
  end

  describe "core" do
    test "#start_battle!", %{strong_hero: attacker, alternate_hero: defender} do
      battle = build_basic_battle(attacker, defender) |> Engine.start_battle!()

      assert battle.initiator == attacker
      assert length(battle.turns) == 0

      no_speed = %{attacker | speed: 0, level: 3}
      battle = build_basic_battle(no_speed, defender) |> Engine.start_battle!()

      assert battle.initiator.id == defender.id
      assert length(battle.turns) == 1
    end

    test "#continue_battle! default case", %{strong_hero: attacker, alternate_hero: defender} do
      battle = create_basic_battle(attacker, defender) |> Engine.continue_battle!(%{skill: nil, item: nil})
      assert length(battle.turns) > 0
    end

    test "#continue_battle! uses skill", %{strong_hero: attacker, alternate_hero: defender} do
      skill = base_skill()
      battle = create_basic_battle(attacker, defender) |> Engine.continue_battle!(%{skill: skill, item: nil})

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)

      assert previous_turn.skill.code == skill.code
      assert previous_turn.attacker.cooldowns == %{"decay" => 1}
    end

    test "#continue_battle! uses skill on cooldown", %{strong_hero: attacker, alternate_hero: defender} do
      skill = base_skill()

      battle =
        create_basic_battle(attacker, defender)
        |> Engine.continue_battle!(%{skill: skill, item: nil})
        |> Engine.continue_battle!(%{skill: skill, item: nil})

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)
      assert last_turn.number == 4

      assert previous_turn.skill.code == "basic_attack"
      assert previous_turn.attacker.cooldowns == %{"decay" => 0}

      battle =
        battle
        |> Engine.continue_battle!(%{skill: nil, item: nil})
        |> Engine.continue_battle!(%{skill: skill, item: nil})

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)

      assert last_turn.number == 8

      assert previous_turn.skill.code == "decay"
      assert previous_turn.attacker.cooldowns == %{"decay" => 1}
    end

    test "#continue_battle! uses item", %{strong_hero: attacker, alternate_hero: defender} do
      item = base_rare_item()
      attacker = Game.buy_item!(%{attacker | gold: 9999}, item)

      battle =
        create_basic_battle(attacker, defender)
        |> Engine.continue_battle!(%{skill: nil, item: item})

      assert Enum.count(battle.turns) == 2

      last_turn = List.last(battle.turns)
      previous_turn = previous_turn_for(last_turn, battle.turns)

      assert previous_turn.item.code == item.code
      assert previous_turn.attacker.cooldowns == %{"tranquil_boots" => 2}
    end

    test "#auto_finish_battle!", %{strong_hero: attacker, alternate_hero: defender} do
      battle = create_basic_battle(attacker, defender) |> Engine.auto_finish_battle!()
      assert battle.finished
    end

    test "#next_battle_turn", %{strong_hero: attacker, alternate_hero: defender} do
      battle = create_basic_battle(attacker, defender)
      turn = Engine.next_battle_turn(battle)

      assert turn.number == 1
      assert turn.attacker.hero_id == attacker.id
      assert turn.defender.hero_id == defender.id
    end

    test "#last_turn", %{strong_hero: attacker, alternate_hero: defender} do
      last_turn =
        create_basic_battle(attacker, defender)
        |> Engine.continue_battle!(%{skill: nil, item: nil})
        |> Engine.last_turn()

      assert last_turn.number == 2
      assert last_turn.skill.code
    end

    test "#can_use_resource?", %{strong_hero: attacker, alternate_hero: defender} do
      skill = base_skill()
      battle = create_basic_battle(attacker, defender)
      assert Engine.next_battle_turn(battle) |> Engine.can_use_resource?(skill)
      battle = Engine.continue_battle!(battle, %{skill: skill, item: nil})
      refute Engine.next_battle_turn(battle) |> Engine.can_use_resource?(skill)
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
