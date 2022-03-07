defmodule Moba.MobaTest do
  use Moba.DataCase

  describe "pvp_points" do
    test "attacker win" do
      assert Moba.attacker_win_pvp_points(200) == 19
      assert Moba.attacker_win_pvp_points(100) == 14
      assert Moba.attacker_win_pvp_points(80) == 13
      assert Moba.attacker_win_pvp_points(40) == 11
      assert Moba.attacker_win_pvp_points(0) == 9
      assert Moba.attacker_win_pvp_points(-40) == 7
      assert Moba.attacker_win_pvp_points(-80) == 2
      assert Moba.attacker_win_pvp_points(-100) == 2
    end

    test "attacker loss" do
      assert Moba.attacker_loss_pvp_points(100) == -2
      assert Moba.attacker_loss_pvp_points(80) == -2
      assert Moba.attacker_loss_pvp_points(40) == -7
      assert Moba.attacker_loss_pvp_points(0) == -9
      assert Moba.attacker_loss_pvp_points(-40) == -11
      assert Moba.attacker_loss_pvp_points(-80) == -13
      assert Moba.attacker_loss_pvp_points(-100) == -14
      assert Moba.attacker_loss_pvp_points(-200) == -19
    end

    test "defender win" do
      assert Moba.defender_win_pvp_points(100) == 0
      assert Moba.defender_win_pvp_points(80) == 0
      assert Moba.defender_win_pvp_points(40) == 0
      assert Moba.defender_win_pvp_points(0) == 2
      assert Moba.defender_win_pvp_points(-40) == 4
      assert Moba.defender_win_pvp_points(-80) == 6
      assert Moba.defender_win_pvp_points(-100) == 7
      assert Moba.defender_win_pvp_points(-200) == 12
    end

    test "defender loss" do
      assert Moba.defender_loss_pvp_points(200) == -12
      assert Moba.defender_loss_pvp_points(100) == -7
      assert Moba.defender_loss_pvp_points(80) == -6
      assert Moba.defender_loss_pvp_points(40) == -4
      assert Moba.defender_loss_pvp_points(0) == -2
      assert Moba.defender_loss_pvp_points(-40) == 0
      assert Moba.defender_loss_pvp_points(-80) == 0
      assert Moba.defender_loss_pvp_points(-100) == 0
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
  end
end
