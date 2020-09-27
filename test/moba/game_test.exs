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
    test "#can_create_new_hero?" do
      user = create_user()

      assert Game.can_create_new_hero?(user)

      create_base_hero(%{}, user)

      assert Game.can_create_new_hero?(user)

      create_base_hero(%{}, user)

      refute Game.can_create_new_hero?(user)
    end

    test "#create_hero!" do
      avatar = base_avatar()
      skills = base_skills()

      hero = Game.create_hero!(%{name: "Foo"}, create_user(), avatar, skills)
      hero = Game.get_hero!(hero.id)
      targets = Game.list_targets(hero.id)

      assert hero.active_build.type == "pve"
      assert length(hero.active_build.skills) == 4
      assert length(targets) > 0
    end

    test "#create_bot_hero! pve" do
      avatar = base_avatar()
      match = Game.current_match()

      bot_level_10 = Game.create_bot_hero!(avatar, 10, "strong", match)

      assert bot_level_10.level == 10
      refute bot_level_10.pvp_last_picked
      refute bot_level_10.pvp_active

      bot_level_0 = Game.create_bot_hero!(avatar, 0, "weak", match)

      assert bot_level_0.atk < avatar.atk
      assert bot_level_0.total_hp < avatar.total_hp
      assert bot_level_0.total_mp < avatar.total_mp
    end

    test "#create_bot_hero! pvp" do
      user = create_user()
      avatar = base_avatar()
      match = Game.current_match()

      bot = Game.create_bot_hero!(avatar, 10, "strong", match, user)

      assert bot.pvp_active
      assert bot.pvp_last_picked
    end

    test "#update_hero!" do
      %{id: id} = hero = create_base_hero()
      Game.subscribe_to_hero(id)
      updated = Game.update_hero!(hero, %{gold: 15}, [base_item()])

      assert updated.gold == 15
      assert updated.items |> List.first() == base_item()
      assert_receive {"hero", %{id: id}}
    end

    test "#update_attacker!" do
      hero = create_base_hero()
      updates = %{total_xp: 200, gold: 50}
      updated = Game.update_attacker!(hero, updates)
      assert updated.level == 2
      assert updated.gold == 50
      assert updated.experience == 80
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

      assert prepared.pvp_points == 100
      assert prepared.pvp_wins == 0
      assert prepared.pvp_losses == 0
      assert prepared.pvp_picks == 1
      assert prepared.pvp_last_picked
      assert prepared.pvp_active
      refute prepared.pvp_ranking
      refute weak_bot.pvp_active
    end

    test "#max_league?" do
      assert build_base_hero(%{league_tier: 5}) |> Game.max_league?()
      refute build_base_hero(%{league_tier: 4}) |> Game.max_league?()
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
      hero1 = create_pvp_hero(%{pvp_points: 1000})
      hero2 = create_pvp_hero(%{pvp_points: 1020})

      Game.update_ranking!()

      hero1 = Game.get_hero!(hero1.id)
      hero2 = Game.get_hero!(hero2.id)

      assert hero1.pvp_ranking == 2
      assert hero2.pvp_ranking == 1
    end

    test "#redeem_league!" do
      hero = create_base_hero(%{pve_points: 15})
      assert Game.redeem_league!(hero) == hero

      hero = create_base_hero(%{pve_points: 20}) |> Game.redeem_league!()

      assert hero.pve_points == 10
      assert hero.league_step == 1
    end

    test "#hero_has_other_build?" do
      hero = create_base_hero()

      refute Game.hero_has_other_build?(hero)

      hero = Game.create_pvp_build!(hero, base_skills())

      assert Game.hero_has_other_build?(hero)
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
      hero = create_base_hero(%{level: 10}) |> Game.create_pvp_build!(alternate_skills())

      assert hero.skill_levels_available == 5
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

      assert hero.active_build.type == "pve"
      assert hero.active_build.item_order
      assert hero.active_build.skill_order
      assert length(hero.items) > 0
    end

    test "#reset_item_orders!" do
      hero = create_bot_hero(0, 25)
      previous_order = hero.active_build.item_order
      build = Game.update_build!(hero.active_build, %{item_order: ["whatever"]})
      assert build.item_order == ["whatever"]
      hero = Game.reset_item_orders!(hero)
      assert List.first(hero.builds).item_order == previous_order
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
      last_league_hero = create_base_hero(%{league_tier: 5, league_step: 5})

      first_league_defender = Game.league_defender_for(first_league_hero)
      last_league_defender = Game.league_defender_for(last_league_hero)

      assert first_league_defender.level >= 6
      assert first_league_defender.bot_difficulty == "weak"
      assert last_league_defender.level >= 25
      assert last_league_defender.bot_difficulty == "strong"
    end
  end

  describe "targets" do
    test "#generate_targets!" do
      hero = create_base_hero() |> Game.generate_targets!()
      assert length(hero.targets) == 6
      assert hero.targets |> Enum.filter(&(&1.difficulty == "weak")) |> length() == 2
      assert hero.targets |> Enum.filter(&(&1.difficulty == "moderate")) |> length() == 2
      assert hero.targets |> Enum.filter(&(&1.difficulty == "strong")) |> length() == 2
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

      catch_error(Game.buy_item!(hero, base_item()))

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
end
