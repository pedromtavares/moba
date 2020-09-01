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
      assert Moba.xp_to_next_hero_level(2) == 140
      assert Moba.xp_to_next_hero_level(5) == 260
      assert Moba.xp_to_next_hero_level(10) == 460
      assert Moba.xp_to_next_hero_level(15) == 660
      assert Moba.xp_to_next_hero_level(20) == 860
      assert Moba.xp_to_next_hero_level(25) == 1060
    end

    test "#xp_until_hero_level" do
      assert Moba.xp_until_hero_level(5) == 800
      assert Moba.xp_until_hero_level(10) == 2700
      assert Moba.xp_until_hero_level(15) == 5600
      assert Moba.xp_until_hero_level(20) == 9500
      assert Moba.xp_until_hero_level(25) == 14400
    end
  end
end
