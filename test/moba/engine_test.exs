defmodule Moba.EngineTest do
  use Moba.DataCase

  setup do
    attrs = %{pvp_points: 50}

    base_hero = create_base_hero(attrs)
    weak_hero = create_base_hero(attrs, create_user(attrs), weak_avatar())

    strong_hero =
      create_base_hero(Map.merge(attrs, %{buffed_battles_available: 1}), create_user(attrs), strong_avatar())

    alternate_hero = create_base_hero(attrs, create_user(attrs), strong_avatar())

    %{weak_hero: weak_hero, strong_hero: strong_hero, base_hero: base_hero, alternate_hero: alternate_hero}
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
      updated = %{attacker | pve_battles_available: 0}
      assert {:error, _} = Engine.create_pve_battle!(%{attacker: updated, defender: defender, difficulty: "weak"})
    end

    test "battle ties and attacker gains xp", %{strong_hero: attacker, alternate_hero: defender} do
      battle =
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "weak"})
        |> Engine.auto_finish_battle!()

      assert battle.type == "pve"

      rewards = battle.rewards
      assert rewards.battle_xp == 70
      assert rewards.difficulty_percentage == 70
      assert rewards.win_xp == 0
      assert rewards.total_xp == 70
      assert rewards.total_pve_points == 1

      reloaded_attacker = Game.Heroes.get!(attacker.id)
      reloaded_defender = Game.Heroes.get!(defender.id)

      assert reloaded_attacker.experience != attacker.experience
      assert reloaded_defender.experience == defender.experience
      assert reloaded_attacker.ties == 1
      assert reloaded_attacker.win_streak == 0
      assert reloaded_attacker.loss_streak == 0

      assert reloaded_attacker.pve_battles_available == attacker.pve_battles_available - 1
      assert reloaded_defender.pve_battles_available == defender.pve_battles_available

      assert reloaded_attacker.experience == 70
      assert reloaded_attacker.gold == attacker.gold + 70
      assert reloaded_attacker.pve_points == attacker.pve_points + 1
    end

    test "battle win for attacker, level up", %{strong_hero: attacker, weak_hero: defender} do
      battle =
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "strong"})
        |> Engine.auto_finish_battle!()

      assert battle.winner.id == attacker.id

      battle = Engine.get_battle!(battle.id)
      assert battle.winner.id == attacker.id

      rewards = battle.rewards
      assert rewards.battle_xp == 200
      assert rewards.difficulty_percentage == 200
      assert rewards.win_xp == 200
      assert rewards.total_xp == 400
      assert rewards.total_pve_points == 6

      updated_attacker = Game.Heroes.get!(attacker.id)
      defender = Game.Heroes.get!(defender.id)

      assert updated_attacker.experience != attacker.experience
      assert updated_attacker.level != attacker.level
      assert updated_attacker.win_streak == 1
      assert updated_attacker.wins == 1
      assert updated_attacker.loss_streak == 0
      assert updated_attacker.buffed_battles_available == 0
      assert updated_attacker.xp_boosted_battles_available == attacker.xp_boosted_battles_available - 1

      assert defender.experience == 0
      assert defender.loss_streak == 0
      assert defender.win_streak == 0
    end

    test "battle loss for attacker, no xp, loss streak", %{weak_hero: attacker, strong_hero: defender} do
      battle =
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "strong"})
        |> Engine.auto_finish_battle!()

      assert battle.winner.id == defender.id

      attacker = Game.Heroes.get!(attacker.id)
      defender = Game.Heroes.get!(defender.id)

      assert attacker.experience == 0
      assert attacker.level == 1
      assert attacker.win_streak == 0
      assert attacker.loss_streak == 1
      assert attacker.losses == 1
      assert battle.rewards.total_pve_points == 0

      assert defender.experience == 0
      assert defender.loss_streak == 0
      assert defender.win_streak == 0
    end

    test "win streak xp for attacker", %{weak_hero: defender, strong_hero: strong} do
      attacker = Game.update_hero!(strong, %{win_streak: 20})

      battle =
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "weak"})
        |> Engine.auto_finish_battle!()

      assert battle.winner.id == attacker.id
      assert battle.rewards.win_streak_xp == 50
    end

    test "loss streak xp for attacker", %{weak_hero: defender, strong_hero: strong} do
      attacker = Game.update_hero!(strong, %{loss_streak: 2})

      battle =
        Engine.create_pve_battle!(%{attacker: attacker, defender: defender, difficulty: "weak"})
        |> Engine.auto_finish_battle!()

      assert battle.winner.id == attacker.id
      assert battle.rewards.loss_streak_xp == 15
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
      Engine.create_pvp_battle!(%{attacker: attacker, defender: defender})
      |> Engine.auto_finish_battle!()

      hero = Game.get_hero!(attacker.id)
      defender = Game.get_hero!(defender.id)

      assert hero.pvp_points == attacker.pvp_points + 15
      assert hero.user.pvp_points == attacker.user.pvp_points + 15

      assert hero.pvp_wins == attacker.pvp_wins + 1
      assert hero.user.pvp_wins == attacker.user.pvp_wins + 1
      assert hero.user.pvp_score == %{"#{defender.user.id}" => 1}
      assert defender.user.pvp_score == %{}
    end

    test "defender wins", %{strong_hero: defender, weak_hero: attacker} do
      Engine.create_pvp_battle!(%{attacker: attacker, defender: defender})
      |> Engine.auto_finish_battle!()

      updated_attacker = Game.get_hero!(attacker.id)
      updated_defender = Game.get_hero!(defender.id)

      assert updated_attacker.pvp_points == attacker.pvp_points - 15
      assert updated_defender.pvp_points == defender.pvp_points + 5
      assert updated_attacker.pvp_losses == attacker.pvp_losses + 1
      assert updated_defender.pvp_wins == defender.pvp_wins + 1
      assert updated_defender.user.pvp_wins == defender.user.pvp_wins + 1
      assert updated_defender.user.pvp_score == %{"#{attacker.user.id}" => 1}
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
      assert hero.buffed_battles_available == Moba.league_win_buffed_battles_bonus()
      assert hero.gold == attacker.gold + Moba.league_win_gold_bonus()
    end
  end

  describe "core" do
    test "#start_battle!", %{strong_hero: attacker, alternate_hero: defender} do
      battle = build_basic_battle(attacker, defender) |> Engine.start_battle!()

      assert battle.initiator == attacker
      assert length(battle.turns) == 0

      no_speed = %{attacker | speed: 0, level: 3}
      battle = build_basic_battle(no_speed, defender) |> Engine.start_battle!()

      assert battle.initiator == defender
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
