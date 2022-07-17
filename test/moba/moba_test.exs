defmodule Moba.MobaTest do
  use Moba.DataCase

  describe "duel points" do
    test "victory" do
      # Enum.each((-100..100), fn n -> IO.inspect("#{n} - #{Moba.victory_duel_points(n)}") end)
      assert Moba.victory_duel_points(200) == 30
      assert Moba.victory_duel_points(100) == 15
      assert Moba.victory_duel_points(80) == 12
      assert Moba.victory_duel_points(40) == 6
      assert Moba.victory_duel_points(20) == 5
      assert Moba.victory_duel_points(0) == 5
      assert Moba.victory_duel_points(-20) == 5
      assert Moba.victory_duel_points(-40) == 4
      assert Moba.victory_duel_points(-50) == 3
      assert Moba.victory_duel_points(-80) == 2
      assert Moba.victory_duel_points(-100) == 2
      assert Moba.victory_duel_points(-200) == 2
    end

    test "tie" do
      assert Moba.tie_duel_points(100) == 5
      assert Moba.tie_duel_points(80) == 4
      assert Moba.tie_duel_points(40) == 2
      assert Moba.tie_duel_points(20) == 2
      assert Moba.tie_duel_points(0) == 2
      assert Moba.tie_duel_points(-20) == -2
      assert Moba.tie_duel_points(-40) == -2
      assert Moba.tie_duel_points(-80) == -4
      assert Moba.tie_duel_points(-100) == -5
      assert Moba.tie_duel_points(-200) == -10
    end
  end

  describe "cross-domain functions" do
    test "#create_current_pve_hero!" do
      player = create_player!()
      avatar = base_avatar()
      skills = base_skills()

      hero = Moba.create_current_pve_hero!(%{name: "Foo"}, player, avatar, skills)
      hero = Game.get_hero!(hero.id)
      player = Game.get_player!(player.id)

      assert hero
      assert player.current_pve_hero_id == hero.id
    end
  end
end
