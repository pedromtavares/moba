defmodule Moba.GameTest do
  use Moba.DataCase

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
      assert hero.gold == 1000
      assert length(hero.active_build.skills) == 4
      assert length(targets) > 0

      veteran_hero = Game.create_hero!(%{name: "Foo"}, create_user(%{pve_tier: 1}), avatar, skills)
      assert veteran_hero.gold == 2000
    end

    test "#create_bot_hero! pve" do
      avatar = base_avatar()

      bot_level_10 = Game.create_bot_hero!(avatar, 10, "strong")

      assert bot_level_10.level == 10
      assert bot_level_10.league_tier == 1
      refute bot_level_10.pvp_last_picked
      refute bot_level_10.pvp_active

      bot_level_0 = Game.create_bot_hero!(avatar, 0, "weak")

      assert bot_level_0.league_tier == 0
      assert bot_level_0.atk < avatar.atk
      assert bot_level_0.total_hp < avatar.total_hp
      assert bot_level_0.total_mp < avatar.total_mp
    end

    test "#create_bot_hero! pvp" do
      user = create_user()
      avatar = base_avatar()

      bot = Game.create_bot_hero!(avatar, 25, "strong", user)

      assert bot.league_tier == 5
      assert bot.pvp_active
      assert bot.pvp_last_picked
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
      updates = %{total_xp: 200, gold: 50}
      updated = Game.update_attacker!(hero, updates)
      assert updated.level == 2
      assert updated.gold == 50
      assert updated.experience == 30
      assert updated.skill_levels_available == 1
      assert updated.total_hp > hero.total_hp
      assert updated.total_mp > hero.total_mp
      assert updated.atk > hero.atk
      assert updated.speed == hero.speed
      assert updated.power == hero.power
      assert updated.armor == hero.armor

      max_league_hero = create_base_hero(%{league_tier: 5})
      updated = Game.update_attacker!(max_league_hero, updates)
      assert updated.level == 25
    end

    test "#prepare_hero_for_pvp!" do
      user = create_user(%{pvp_points: 100})
      hero = create_base_hero(%{}, user) |> Game.buy_item!(base_item())
      weak_bot = create_bot_hero(-100)

      prepared = Game.prepare_hero_for_pvp!(hero)
      weak_bot = Game.get_hero!(weak_bot.id)

      hero_skills = hero.active_build.skills
      prepared_skills = prepared.active_build.skills

      assert length(hero.items) == length(prepared.items)
      assert length(hero_skills) == length(prepared.active_build.skills)

      assert Enum.map(hero_skills, fn skill -> skill.level end) |> Enum.sum() ==
               Enum.map(prepared_skills, fn skill -> skill.level end) |> Enum.sum()

      assert prepared.pvp_points == 0
      assert prepared.pvp_wins == 0
      assert prepared.pvp_losses == 0
      assert prepared.pvp_picks == 1
      assert prepared.pvp_last_picked
      assert prepared.pvp_active
      refute prepared.pvp_ranking
      refute weak_bot.pvp_active
      assert prepared.match_id == Game.current_match().id
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

    test "#update_pvp_ranking" do
      hero1 = create_pvp_hero(%{league_tier: 5}, 1000)
      hero2 = create_pvp_hero(%{league_tier: 5}, 1020)

      Game.update_pvp_rankings!()

      hero1 = Game.get_hero!(hero1.id)
      hero2 = Game.get_hero!(hero2.id)

      assert hero1.pvp_ranking == 2
      assert hero2.pvp_ranking == 1
    end

    test "#update_pve_ranking" do
      hero1 = create_base_hero(%{total_farm: 100, pve_battles_available: 0, finished_pve: true})
      hero2 = create_base_hero(%{total_farm: 200, pve_battles_available: 0, finished_pve: true})

      Game.update_pve_ranking!()

      hero1 = Game.get_hero!(hero1.id)
      hero2 = Game.get_hero!(hero2.id)

      assert hero1.pve_ranking == 2
      assert hero2.pve_ranking == 1
    end

    test "#redeem_league!" do
      hero = create_base_hero(%{pve_points: 10})
      assert Game.redeem_league!(hero) == hero

      hero = create_base_hero(%{pve_points: 22}) |> Game.redeem_league!()

      assert hero.pve_points == 0
      assert hero.league_step == 1
    end

    test "#redeem_league! when in master league" do
      hero =
        create_base_hero(%{league_tier: Moba.master_league_tier(), pve_points: Moba.pve_points_limit()})
        |> Game.generate_boss!()
        |> Game.redeem_league!()

      assert hero.league_step == 1
      assert hero.pve_points == Moba.pve_points_limit()
    end

    test "#hero_has_other_build?" do
      hero = create_base_hero()

      refute Game.hero_has_other_build?(hero)

      hero = Game.create_pvp_build!(hero, base_skills())

      assert Game.hero_has_other_build?(hero)
    end

    test "#maybe_finish_pve" do
      hero = create_base_hero()

      assert Game.maybe_finish_pve(hero) == hero

      hero = create_base_hero() |> Game.generate_boss!()

      assert Game.maybe_finish_pve(hero) == hero

      hero = create_base_hero(%{pve_battles_available: 0, pve_points: 0}) |> Game.maybe_finish_pve()

      assert hero.finished_pve

      hero =
        create_base_hero(%{
          pve_battles_available: 0,
          pve_points: Moba.pve_points_limit(),
          league_tier: Moba.master_league_tier()
        })

      assert Game.maybe_finish_pve(hero) == hero

      hero =
        create_base_hero(%{
          pve_battles_available: 0,
          pve_points: Moba.pve_points_limit(),
          league_tier: Moba.max_league_tier()
        })
        |> Game.maybe_finish_pve()

      assert hero.finished_pve
    end

    test "#finish_pve!" do
      user = create_user()
      hero = create_base_hero(%{league_tier: 4}, user)
      finished = Game.finish_pve!(hero)

      assert finished.finished_pve
      assert finished.shards_reward == 40
    end

    test "#maybe_generate_boss" do
      hero =
        create_base_hero(%{
          pve_battles_available: 0,
          league_tier: Moba.master_league_tier(),
          pve_points: Moba.pve_points_limit()
        })

      assert Game.maybe_generate_boss(hero).boss_id

      hero =
        create_base_hero(%{pve_battles_available: 0, league_tier: Moba.master_league_tier()}) |> Game.generate_boss!()

      assert Game.maybe_generate_boss(hero) == hero

      hero = create_base_hero()

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
      assert hero.pve_points == 11
      refute hero.boss_id
    end

    test "#buyback!" do
      hero = create_base_hero()

      assert Game.buyback!(hero) == hero

      hero = create_base_hero(%{gold: 1000, level: 10, dead: true, total_farm: 1000})
      updated = Game.buyback!(hero)

      price = Game.buyback_price(hero)

      refute updated.dead
      assert updated.buybacks == 1
      assert updated.gold == hero.gold - price
      assert updated.total_farm == hero.total_farm - price

      veteran_hero =
        create_base_hero(%{gold: 1000, level: 10, dead: true, total_farm: 1000}, create_user(%{pve_tier: 2}))

      veteran_price = Game.buyback_price(veteran_hero)

      assert veteran_price == price / 2
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

    test "#create_pvp_build!" do
      hero = create_base_hero(%{level: 25}) |> Game.create_pvp_build!(alternate_skills())
      skills = hero.active_build.skills
      normals = Enum.filter(skills, &(!&1.ultimate))
      ultimate = Enum.find(skills, & &1.ultimate)

      assert List.first(normals).level == 5
      assert ultimate.level == 3
      assert hero.active_build.type == "pvp"
    end

    test "#switch_build!" do
      hero =
        create_base_hero(%{level: 10})
        |> Game.create_pvp_build!(alternate_skills())
        |> Game.switch_build!()

      assert hero.active_build.type == "pve"
    end

    test "#generate_bot_build!" do
      hero =
        create_base_hero(%{bot_difficulty: "strong", level: 25, gold: 999_999})
        |> Game.generate_bot_build!()

      assert hero.active_build.type == "pvp"
      assert hero.active_build.item_order
      assert hero.active_build.skill_order
      assert length(hero.items) > 0
    end

    test "#reset_item_orders!" do
      base_hero = create_base_hero(%{bot_difficulty: "strong", level: 25, gold: 999_999}) |> Game.generate_bot_build!()
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

      assert first_league_defender.level >= 6
      assert first_league_defender.bot_difficulty == "weak"
      assert diamond_league_defender.level >= 25
      assert diamond_league_defender.bot_difficulty == "strong"
      assert master_league_defender.avatar.code == "boss"
    end
  end

  describe "targets" do
    test "#generate_targets! user tier 0 easy_mode" do
      hero = create_base_hero(%{easy_mode: true}, create_user(%{pve_tier: 0})) |> Game.generate_targets!()
      assert length(hero.targets) == 6
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 2
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 2
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 2
    end

    test "#generate_targets! user tier 0" do
      hero = create_base_hero(%{}, create_user(%{pve_tier: 0})) |> Game.generate_targets!()
      assert length(hero.targets) == 9
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 3
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 3
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 3
    end

    test "#generate_targets! user tier 1" do
      hero = create_base_hero(%{}, create_user(%{pve_tier: 1})) |> Game.generate_targets!()
      assert length(hero.targets) == 9
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 3
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 3
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 3
    end

    test "#generate_targets! user tier 2" do
      hero = create_base_hero(%{}, create_user(%{pve_tier: 2})) |> Game.generate_targets!()
      assert length(hero.targets) == 9
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 0
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 3
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 6
    end

    test "#generate_targets! user tier 3" do
      hero = create_base_hero(%{}, create_user(%{pve_tier: 3})) |> Game.generate_targets!()
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
    end

    test "#transmute_item!" do
      base_hero = create_base_hero(%{gold: 5000}) |> Repo.preload(:items)
      normal_items = base_normal_items()
      rare = base_rare_item()

      catch_error(Game.transmute_item!(base_hero, normal_items, rare))

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

      hero_with_full_inventory = create_bot_hero(0, 40, "strong")

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

      duel = Game.create_duel!(user, opponent)

      assert duel.phase == "user_first_pick"

      Game.next_duel_phase!(duel, user_hero.id)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "opponent_first_pick"
      assert duel.user_first_pick_id == user_hero.id

      Game.next_duel_phase!(duel, opp_hero.id)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "user_battle"
      assert duel.opponent_first_pick_id == opp_hero.id

      battle = Engine.first_duel_battle(duel)

      assert battle.attacker_id == user_hero.id
      assert battle.defender_id == opp_hero.id

      Engine.auto_finish_battle!(battle)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "opponent_second_pick"

      Game.next_duel_phase!(duel, opp_hero.id)
      duel = Game.get_duel!(duel.id)

      assert duel.phase == "user_second_pick"

      Game.next_duel_phase!(duel, user_hero.id)
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
end
