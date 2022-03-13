defmodule Moba.GameTest do
  use Moba.DataCase, async: true

  describe "matches" do
    test "#current_match" do
      assert Game.current_match().active
    end

    test "#create_match!" do
      match = Game.create_match!(%{next_changelog: "hi"})
      assert match.next_changelog == "hi"
    end

    test "update_match!" do
      match = Game.update_match!(Moba.current_match(), %{next_changelog: "hi"})
      assert match.next_changelog == "hi"
    end
  end

  describe "heroes" do
    test "#create_hero!" do
      avatar = base_avatar()
      skills = base_skills()

      hero = Game.create_hero!(%{name: "Foo"}, create_user(), avatar, skills)
      hero = Game.get_hero!(hero.id)
      targets = Game.list_targets(hero)

      assert hero.active_build.type == "pve"
      assert hero.gold == 800
      assert length(hero.active_build.skills) == 4
      assert length(targets) > 0

      veteran_hero = Game.create_hero!(%{name: "Foo"}, create_user(%{pve_tier: 1}), avatar, skills)
      assert veteran_hero.gold == 2000
    end

    test "#create_bot_hero! pve" do
      avatar = base_avatar()

      bot_level_7 = Game.create_bot_hero!(avatar, 7, "strong")

      assert bot_level_7.level == 7
      assert bot_level_7.league_tier == 1
      refute bot_level_7.pvp_last_picked
      refute bot_level_7.pvp_active

      bot_level_0 = Game.create_bot_hero!(avatar, 0, "weak")

      assert bot_level_0.league_tier == 0
      assert bot_level_0.atk < avatar.atk
      assert bot_level_0.total_hp < avatar.total_hp
      assert bot_level_0.total_mp < avatar.total_mp
    end

    test "#update_hero!" do
      %{id: id} = hero = create_base_hero()
      Game.subscribe_to_hero(id)
      updated = Game.update_hero!(hero, %{gold: 15}, [base_item()])

      assert updated.gold == 15
      assert updated.items |> List.first() == base_item()
      assert_receive {"hero", %{id: _id}}
    end

    test "#update_attacker!" do
      hero = create_base_hero()
      updates = %{total_xp: 650, gold: 50}
      updated = Game.update_attacker!(hero, updates)
      assert updated.level == 2
      assert updated.gold == 50
      assert updated.experience == 50
      assert updated.skill_levels_available == 1
      assert updated.total_hp > hero.total_hp
      assert updated.total_mp > hero.total_mp
      assert updated.atk > hero.atk
      assert updated.speed == hero.speed
      assert updated.power == hero.power
      assert updated.armor == hero.armor

      hero = create_base_hero(%{level: 28})
      updates = %{total_xp: 10_000}
      updated = Game.update_attacker!(hero, updates)

      assert updated.level > 28
      assert updated.skill_levels_available == 0
    end

    test "#max_league?" do
      assert build_base_hero(%{league_tier: 6}) |> Game.max_league?()
      refute build_base_hero(%{league_tier: 5}) |> Game.max_league?()
    end

    test "#master_league?" do
      assert build_base_hero(%{league_tier: 5}) |> Game.master_league?()
      refute build_base_hero(%{league_tier: 6}) |> Game.master_league?()
    end

    test "#pve_win_rate" do
      hero = build_base_hero(%{wins: 60, ties: 20, losses: 20})
      assert Game.pve_win_rate(hero) == 60
      assert build_base_hero() |> Game.pve_win_rate() == 0
    end

    test "#pvp_win_rate?" do
      hero = build_base_hero(%{pvp_wins: 60, pvp_losses: 40})
      assert Game.pvp_win_rate(hero) == 60
      assert build_base_hero() |> Game.pvp_win_rate() == 0
    end

    test "#update_pve_ranking" do
      hero1 = create_base_hero(%{total_gold_farm: 100, pve_current_turns: 0, finished_at: Timex.now()})
      hero2 = create_base_hero(%{total_gold_farm: 200, pve_current_turns: 0, finished_at: Timex.now()})

      Game.update_pve_ranking!()

      hero1 = Game.get_hero!(hero1.id)
      hero2 = Game.get_hero!(hero2.id)

      assert hero1.pve_ranking == 2
      assert hero2.pve_ranking == 1
    end

    test "#maybe_finish_pve" do
      hero = create_base_hero()

      assert Game.maybe_finish_pve(hero) == hero

      hero = create_base_hero() |> Game.generate_boss!()

      assert Game.maybe_finish_pve(hero) == hero

      hero = create_base_hero(%{pve_current_turns: 0, pve_total_turns: 0, pve_state: "dead"}) |> Game.maybe_finish_pve()

      assert hero.finished_at

      hero =
        create_base_hero(%{
          pve_current_turns: 0,
          pve_total_turns: 5,
          league_tier: Moba.master_league_tier()
        })

      assert Game.maybe_finish_pve(hero) == hero

      hero =
        create_base_hero(%{
          pve_current_turns: 0,
          pve_total_turns: 0,
          pve_tier: 4,
          league_tier: Moba.max_league_tier()
        })
        |> Game.maybe_finish_pve()

      assert hero.finished_at

      hero =
        create_base_hero(%{
          pve_current_turns: 0,
          pve_total_turns: 0,
          pve_tier: 0,
          league_tier: 4
        })
        |> Game.maybe_finish_pve()

      assert hero.finished_at

      hero =
        create_base_hero(%{
          pve_current_turns: 0,
          pve_total_turns: 0,
          pve_tier: 4,
          league_tier: 5,
          boss_id: nil
        })
        |> Game.maybe_finish_pve()

      assert hero.finished_at
    end

    test "#finish_pve!" do
      user = create_user()
      hero = create_base_hero(%{league_tier: 5}, user)
      finished = Game.finish_pve!(hero)

      assert finished.finished_at

      quest = Game.Quests.get_by_code_and_level!("season", 1)
      progression = Game.Quests.find_progression_by!(user.id, quest.id)

      assert progression.current_value == 1
      refute progression.completed_at

      user = Accounts.get_user!(user.id)

      create_base_hero(%{league_tier: 5}, user, alternate_avatar()) |> Game.finish_pve!()
      progression = Game.Quests.find_progression_by!(user.id, quest.id)

      assert progression.current_value == 2
      assert progression.completed_at

      updated = Accounts.get_user!(user.id)

      assert updated.pve_tier == 1
      assert updated.shard_count == user.shard_count + quest.shard_prize
    end

    test "#maybe_generate_boss" do
      hero =
        create_base_hero(%{
          pve_current_turns: 5,
          pve_total_turns: 0,
          league_tier: Moba.master_league_tier()
        })

      assert Game.maybe_generate_boss(hero).boss_id

      hero = create_base_hero(%{pve_current_turns: 0, league_tier: Moba.master_league_tier()}) |> Game.generate_boss!()

      assert Game.maybe_generate_boss(hero) == hero

      hero = create_base_hero(%{pve_current_turns: 5, pve_state: "dead", league_tier: Moba.master_league_tier()})

      refute Game.maybe_generate_boss(hero).boss_id
    end

    test "#generate_boss!" do
      hero = create_base_hero() |> Game.generate_boss!()

      hero = Game.get_hero!(hero.id)

      assert hero.boss_id

      boss = Game.get_hero!(hero.boss_id)

      assert boss.boss_id == hero.id
    end

    test "#finalize_boss!" do
      hero = create_base_hero() |> Game.generate_boss!()
      boss = Game.get_hero!(hero.boss_id)

      assert boss.league_attempts == 0

      hero = Game.finalize_boss!(boss, 1000, hero)

      boss = Game.get_hero!(hero.boss_id)

      assert boss.total_hp == 2500
      assert boss.league_attempts == 1

      hero = Game.finalize_boss!(boss, 0, hero)
      refute hero.boss_id
    end

    test "#buyback!" do
      hero = create_base_hero()

      assert Game.buyback!(hero) == hero

      hero = create_base_hero(%{gold: 1000, level: 10, pve_state: "dead", total_gold_farm: 1000})
      updated = Game.buyback!(hero)

      price = Game.buyback_price(hero)

      refute updated.pve_state == "dead"
      assert updated.buybacks == 1
      assert updated.gold == hero.gold - price
      assert updated.total_gold_farm == hero.total_gold_farm - price
    end

    test "#start_farming!" do
      hero = create_base_hero()
      updated = Game.start_farming!(hero, "meditating", 5)

      assert updated.pve_state == "meditating"
      assert updated.pve_farming_turns == 5
      refute is_nil(updated.pve_farming_started_at)
    end

    test "#finish_farming!" do
      hero = create_base_hero(%{pve_current_turns: 5}) |> Game.start_farming!("meditating", 5)
      targets = Game.generate_targets!(hero) |> Map.get(:targets) |> Enum.map(& &1.id) |> Enum.sort()
      updated = Game.finish_farming!(hero)

      assert updated.pve_state == "alive"
      assert updated.pve_farming_turns == 0
      assert is_nil(updated.pve_farming_started_at)
      assert updated.pve_current_turns == 0
      assert Game.list_targets(updated) |> Enum.map(& &1.id) |> Enum.sort() != targets
      assert updated.pve_farming_rewards != hero.pve_farming_rewards
      assert updated.total_xp_farm > hero.total_xp_farm

      hero = create_base_hero(%{pve_current_turns: 5}) |> Game.start_farming!("mining", 5)
      updated = Game.finish_farming!(hero)

      assert updated.total_gold_farm > hero.total_gold_farm
    end
  end

  describe "builds" do
    test "#update_build!" do
      skill_order = ["decay", "shuriken_toss"]
      build = base_build() |> Game.update_build!(%{skill_order: skill_order})
      assert build.skill_order == skill_order
    end

    test "#replace_build_skills!" do
      build = base_build() |> Game.replace_build_skills!(alternate_skills())

      assert build.skills == alternate_skills()
    end

    test "#generate_bot_build!" do
      hero =
        create_base_hero(%{bot_difficulty: "strong", level: 25, gold: 999_999, total_gold_farm: 999_999})
        |> Game.generate_bot_build!()

      assert hero.active_build.type == "pvp"
      assert hero.active_build.item_order
      assert hero.active_build.skill_order
      assert length(hero.items) > 0
    end

    test "#reset_item_orders!" do
      base_hero =
        create_base_hero(%{bot_difficulty: "strong", level: 25, gold: 999_999, total_gold_farm: 999_999})
        |> Game.generate_bot_build!()

      reset_hero = Game.reset_item_orders!(base_hero, [base_rare_item()])
      assert List.first(reset_hero.builds).item_order == ["tranquil_boots"]
    end

    test "#skill_builds_for" do
      builds = Game.skill_builds_for("tank")
      assert length(builds) == 3
    end

    test "#skill_build_for" do
      build = Game.skill_build_for("tank", 0)
      assert elem(build, 1) == "Balanced Tank"
    end
  end

  describe "leagues" do
    test "#max_league_step_for" do
      assert Game.max_league_step_for(0) == 2
      assert Game.max_league_step_for(1) == 3
      assert Game.max_league_step_for(2) == 4
      assert Game.max_league_step_for(3) == 5
      assert Game.max_league_step_for(4) == 5
    end

    test "#league_defender_for" do
      first_league_hero = create_base_hero(%{league_tier: 0, league_step: 1})
      diamond_league_hero = create_base_hero(%{league_tier: 4, league_step: 5})
      master_league_hero = create_base_hero(%{league_tier: 5, league_step: 5}) |> Game.generate_boss!()

      first_league_defender = Game.league_defender_for(first_league_hero)
      diamond_league_defender = Game.league_defender_for(diamond_league_hero)
      master_league_defender = Game.league_defender_for(master_league_hero)

      assert first_league_defender.level >= 4
      assert first_league_defender.bot_difficulty == "moderate"
      assert diamond_league_defender.level >= 17
      assert diamond_league_defender.bot_difficulty == "strong"
      assert master_league_defender.avatar.code == "boss"
    end
  end

  describe "targets" do
    test "#generate_targets! user tier 0" do
      hero = create_base_hero(%{}, create_user(%{pve_tier: 0})) |> Game.generate_targets!()
      assert length(hero.targets) == 6
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 3
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 3
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 0
    end

    test "#generate_targets! user tier 1" do
      hero = create_base_hero(%{}, create_user(%{pve_tier: 1})) |> Game.generate_targets!()
      assert length(hero.targets) == 9
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 3
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 6
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 0
    end

    test "#generate_targets! user tier 2" do
      hero = create_base_hero(%{}, create_user(%{pve_tier: 2})) |> Game.generate_targets!()
      assert length(hero.targets) == 9
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 0
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 6
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 3
    end

    test "#generate_targets! user tier 3" do
      hero = create_base_hero(%{}, create_user(%{pve_tier: 3})) |> Game.generate_targets!()
      assert length(hero.targets) == 9
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 0
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 3
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 6
    end

    test "#generate_targets! user tier 4" do
      hero = create_base_hero(%{}, create_user(%{pve_tier: 4})) |> Game.generate_targets!()
      assert length(hero.targets) == 9
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 0
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 0
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 9
    end
  end

  describe "items" do
    test "#buy_item!" do
      base_hero = create_base_hero(%{gold: 5000})
      hero = Game.buy_item!(base_hero, alternate_item())

      assert hero.gold == 200
      assert Enum.member?(hero.items, alternate_item())
      assert hero.item_speed > base_hero.item_speed
      assert hero.item_hp > base_hero.item_hp
      assert hero.item_mp > base_hero.item_mp
      assert hero.item_atk > base_hero.item_atk

      assert hero == Game.buy_item!(hero, base_item())

      Game.buy_item!(%{hero | gold: 10000}, base_item())
      tranquil_boots = base_rare_item()
      more_boots = Game.buy_item!(%{hero | gold: 10000}, tranquil_boots)
      assert more_boots.item_speed == hero.item_speed + tranquil_boots.base_speed
    end

    test "#sell_item!" do
      base_hero = create_base_hero(%{gold: 5000})

      hero =
        base_hero
        |> Game.buy_item!(alternate_item())
        |> Game.sell_item!(alternate_item())

      assert hero.gold == 4520
      refute Enum.member?(hero.items, base_item())
      assert hero.item_speed == base_hero.item_speed
      assert hero.item_hp == base_hero.item_hp
      assert hero.item_mp == base_hero.item_mp
      assert hero.item_atk == base_hero.item_atk

      base_hero = create_base_hero(%{gold: 5000, finished_at: Timex.now()})

      hero =
        base_hero
        |> Game.buy_item!(alternate_item())
        |> Game.sell_item!(alternate_item())

      assert hero.gold == 5000
    end

    test "#transmute_item!" do
      base_hero = create_base_hero(%{gold: 5000}) |> Repo.preload(:items)
      normal_items = base_normal_items()
      rare = base_rare_item()

      assert Game.transmute_item!(base_hero, normal_items, rare) == base_hero

      hero =
        base_hero
        |> Game.update_hero!(%{}, normal_items)
        |> Game.transmute_item!(normal_items, rare)

      assert Enum.member?(hero.items, rare)
      refute Enum.member?(hero.items, List.first(normal_items))
      assert hero.item_speed == rare.base_speed
      assert hero.item_speed > base_hero.item_speed
    end

    test "#can_equip_item?" do
      base_hero = create_base_hero(%{gold: 5000})
      item = base_item()

      assert Game.can_equip_item?(base_hero, item)

      with_item = Game.buy_item!(base_hero, item)

      refute Game.can_equip_item?(with_item, item)
    end

    test "#can_buy_item?" do
      base_hero = create_base_hero(%{gold: 10})
      item = base_item()

      refute Game.can_buy_item?(base_hero, item)

      hero_with_full_inventory = create_bot_hero(40, "strong")

      refute Game.can_buy_item?(hero_with_full_inventory, item)

      hero_with_gold = Game.update_hero!(base_hero, %{gold: 1000})

      assert Game.can_buy_item?(hero_with_gold, item)
    end
  end

  describe "skills" do
    test "#level_up_skill!" do
      base_hero = create_base_hero()
      skill = base_skill()
      assert Game.level_up_skill!(base_hero, skill.code) == base_hero

      hero =
        base_hero
        |> Game.update_hero!(%{skill_levels_available: 1})
        |> Game.level_up_skill!(skill.code)

      assert hero.skill_levels_available == 0

      decay = Enum.find(hero.active_build.skills, fn s -> s.code == skill.code end)
      assert decay.level == 2
    end

    test "#can_level_skill?" do
      base_hero = create_base_hero()
      refute Game.can_level_skill?(base_hero, base_skill())

      hero = Game.update_hero!(base_hero, %{skill_levels_available: 10})

      assert Game.can_level_skill?(hero, base_skill())
      refute Game.can_level_skill?(hero, base_ultimate())

      hero = Game.update_hero!(hero, %{level: 10})
      assert Game.can_level_skill?(hero, base_ultimate())
    end

    test "#max_skill_level" do
      assert Game.max_skill_level(base_skill()) == 5
      assert Game.max_skill_level(base_ultimate()) == 3
    end
  end

  describe "avatars" do
    test "#create_avatar!" do
      avatar = Game.create_avatar!(%Game.Schema.Avatar{ultimate_code: "coup"}, %{name: "test"})

      assert avatar.ultimate == base_ultimate()
    end
  end

  describe "duels" do
    test "#next_duel_phase!" do
      user = create_user()
      opponent = create_user()
      skills = base_skills()

      user_hero = Game.create_hero!(%{name: "User"}, user, strong_avatar(), skills)
      opp_hero = Game.create_hero!(%{name: "Opponent"}, opponent, weak_avatar(), skills)

      duel = Game.create_duel!(user, opponent, "pvp")

      assert duel.phase == "user_first_pick"

      Game.next_duel_phase!(duel, user_hero)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "opponent_first_pick"
      assert duel.user_first_pick_id == user_hero.id

      Game.next_duel_phase!(duel, opp_hero)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "user_battle"
      assert duel.opponent_first_pick_id == opp_hero.id

      battle = Engine.first_duel_battle(duel)

      assert battle.attacker_id == user_hero.id
      assert battle.defender_id == opp_hero.id

      Engine.auto_finish_battle!(battle)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "opponent_second_pick"

      Game.next_duel_phase!(duel, opp_hero)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "user_second_pick"

      Game.next_duel_phase!(duel, user_hero)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "opponent_battle"

      battle = Engine.last_duel_battle(duel)

      assert battle.attacker_id == opp_hero.id
      assert battle.defender_id == user_hero.id

      Engine.auto_finish_battle!(battle)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "finished"
    end
  end

  describe "quests" do
    test "#track_pve master quests" do
      user = create_user()
      skills = base_skills()

      user_hero =
        %{name: "User", league_tier: 5, finished_at: Timex.now()}
        |> Game.create_hero!(user, strong_avatar(), skills)

      Game.track_pve_quests(user_hero)

      assert_progression("season", user_hero, 1)
      assert_progression("season_master", user_hero, 1, 5)
      assert_progression("daily_master", user_hero, 1)
    end

    test "#track_pve grandmaster quests" do
      user = create_user()
      skills = base_skills()

      user_hero =
        %{name: "User", league_tier: 6, finished_at: Timex.now()}
        |> Game.create_hero!(user, strong_avatar(), skills)

      Game.track_pve_quests(user_hero)

      assert_progression("season", user_hero, 1)
      assert_progression("daily_master", user_hero, 1)
      assert_progression("season_master", user_hero, 1, 5)
      assert_progression("season_grandmaster", user_hero, 1, 6)
      assert_progression("daily_grandmaster", user_hero, 1)
    end

    test "#track_pve perfect quests" do
      user = create_user()
      skills = base_skills()

      user_hero =
        %{
          name: "User",
          league_tier: 6,
          finished_at: Timex.now(),
          total_gold_farm: div(Moba.maximum_total_farm(), 2),
          total_xp_farm: div(Moba.maximum_total_farm(), 2)
        }
        |> Game.create_hero!(user, strong_avatar(), skills)

      Game.track_pve_quests(user_hero)

      assert_progression("season", user_hero, 1)
      assert_progression("daily_master", user_hero, 1)
      assert_progression("season_master", user_hero, 1, 5)
      assert_progression("season_grandmaster", user_hero, 1, 6)
      assert_progression("daily_grandmaster", user_hero, 1)
      assert_progression("daily_perfect", user_hero, 1)
      assert_progression("season_perfect", user_hero, 1, 7)
    end
  end

  defp assert_progression(code, %{user_id: user_id, avatar: %{code: avatar_code}}, current_value, quest_level \\ 1) do
    quest = Game.Quests.get_by_code_and_level!(code, quest_level)
    progression = Game.Quests.find_progression_by!(user_id, quest.id)
    assert progression.current_value == current_value

    if current_value > 0 do
      assert progression.history_codes == [avatar_code]
    end
  end
end
