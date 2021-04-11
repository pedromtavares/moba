defmodule Moba.MobaTest do
  use Moba.DataCase

  describe "pvp_points" do
    test "attacker win" do
      assert Moba.attacker_win_pvp_points(200) == 40
      assert Moba.attacker_win_pvp_points(100) == 28
      assert Moba.attacker_win_pvp_points(80) == 25
      assert Moba.attacker_win_pvp_points(40) == 20
      assert Moba.attacker_win_pvp_points(0) == 15
      assert Moba.attacker_win_pvp_points(-40) == 10
      assert Moba.attacker_win_pvp_points(-80) == 5
      assert Moba.attacker_win_pvp_points(-100) == 5
    end

    test "attacker loss" do
      assert Moba.attacker_loss_pvp_points(100) == -5
      assert Moba.attacker_loss_pvp_points(80) == -5
      assert Moba.attacker_loss_pvp_points(40) == -10
      assert Moba.attacker_loss_pvp_points(0) == -15
      assert Moba.attacker_loss_pvp_points(-40) == -20
      assert Moba.attacker_loss_pvp_points(-80) == -25
      assert Moba.attacker_loss_pvp_points(-100) == -28
      assert Moba.attacker_loss_pvp_points(-200) == -40
    end

    test "defender win" do
      assert Moba.defender_win_pvp_points(100) == 0
      assert Moba.defender_win_pvp_points(80) == 0
      assert Moba.defender_win_pvp_points(40) == 0
      assert Moba.defender_win_pvp_points(0) == 5
      assert Moba.defender_win_pvp_points(-40) == 10
      assert Moba.defender_win_pvp_points(-80) == 15
      assert Moba.defender_win_pvp_points(-100) == 18
      assert Moba.defender_win_pvp_points(-200) == 30
    end

    test "defender loss" do
      assert Moba.defender_loss_pvp_points(200) == -30
      assert Moba.defender_loss_pvp_points(100) == -18
      assert Moba.defender_loss_pvp_points(80) == -15
      assert Moba.defender_loss_pvp_points(40) == -10
      assert Moba.defender_loss_pvp_points(0) == -5
      assert Moba.defender_loss_pvp_points(-40) == 0
      assert Moba.defender_loss_pvp_points(-80) == 0
      assert Moba.defender_loss_pvp_points(-100) == 0
    end
  end

  describe "xp calculations" do
    test "#win_streak_xp" do
      assert Moba.win_streak_xp(1) == 0
      assert Moba.win_streak_xp(2) == 10
      assert Moba.win_streak_xp(5) == 40
      assert Moba.win_streak_xp(10) == 90
      assert Moba.win_streak_xp(11) == 100
      assert Moba.win_streak_xp(12) == 100
    end

    test "#loss_streak_xp" do
      assert Moba.loss_streak_xp(1) == 0
      assert Moba.loss_streak_xp(2) == 30
      assert Moba.loss_streak_xp(5) == 120
      assert Moba.loss_streak_xp(10) == 270
      assert Moba.loss_streak_xp(15) == 420
    end

    test "#xp_to_next_hero_level" do
      assert Moba.xp_to_next_hero_level(2) == 120
      assert Moba.xp_to_next_hero_level(5) == 180
      assert Moba.xp_to_next_hero_level(10) == 280
      assert Moba.xp_to_next_hero_level(15) == 380
      assert Moba.xp_to_next_hero_level(20) == 480
      assert Moba.xp_to_next_hero_level(25) == 870
    end

    test "#xp_until_hero_level" do
      assert Moba.xp_until_hero_level(5) == 600
      assert Moba.xp_until_hero_level(10) == 1800
      assert Moba.xp_until_hero_level(15) == 3500
      assert Moba.xp_until_hero_level(20) == 5700
      assert Moba.xp_until_hero_level(25) == 9750
    end
  end

  describe "cross-domain functions" do
    test "#create_current_pve_hero!" do
      user = create_user()
      avatar = base_avatar()
      skills = base_skills()

      hero = Moba.create_current_pve_hero!(%{name: "Foo"}, user, avatar, skills)
      hero = Game.get_hero!(hero.id)
      user = Accounts.get_user!(user.id)

      assert hero
      assert user.current_pve_hero_id == hero.id
    end

    test "#update_attacker!" do
      hero = create_base_hero()
      updates = %{total_xp: 200, gold: 50}
      updated = Moba.update_attacker!(hero, updates)
      assert updated.level == 2
      assert updated.gold == 50

      user = Accounts.get_user!(updated.user_id)
      assert user.experience == 200
    end

    test "#update_defender!" do
      hero = create_base_hero()
      updates = %{gold: 50}
      updated = Moba.update_defender!(hero, updates)

      assert updated.gold == 50

      user = Accounts.get_user!(updated.user_id)
      assert user.experience == 0
    end

    test "#prepare_current_pvp_hero!" do
      user = create_user(%{pvp_points: 100})
      hero = create_base_hero(%{}, user)

      prepared = Moba.prepare_current_pvp_hero!(hero)
      user = Accounts.get_user!(hero.user_id)

      assert user.current_pvp_hero_id == prepared.id
      assert prepared.pvp_active
    end
  end
end
