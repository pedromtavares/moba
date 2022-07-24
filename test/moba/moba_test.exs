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
    test "#shard_buyback! with valid hero" do
      user = create_user(%{shard_count: 100})
      player = create_player!(%{}, user)
      hero = create_base_hero(%{league_tier: 2, pve_tier: 4, pve_state: "dead"}, player) |> Moba.shard_buyback!()
      updated_user = Accounts.get_user!(user.id)

      assert hero.pve_state == "alive"
      assert updated_user.shard_count == 95
    end

    test "#shard_buyback! with invalid hero" do
      user = create_user(%{shard_count: 100})
      player = create_player!(%{}, user)
      hero = create_base_hero(%{league_tier: 4, pve_tier: 2, pve_state: "dead"}, player) |> Moba.shard_buyback!()
      updated_user = Accounts.get_user!(user.id)

      assert hero.pve_state == "dead"
      assert updated_user.shard_count == 100
    end

    test "#reward_shards!" do
      player = create_player!() |> Repo.preload(:user)

      Moba.reward_shards!(player, 200)

      user = Accounts.get_user!(player.user_id)

      assert user.shard_count == 200
    end
  end
end
