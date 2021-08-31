defmodule Moba.AccountsTest do
  use Moba.DataCase

  setup do
    %{user: create_user()}
  end

  describe "user updates" do
    test "#update_tutorial_step", %{user: user} do
      user = Accounts.update_tutorial_step!(user, 5)
      assert user.tutorial_step == 5
    end

    test "#set_user_online_now", %{user: user} do
      {1, nil} = Accounts.set_user_online_now(user)
      user = Accounts.get_user!(user.id)

      assert user.last_online_at
    end

    test "#set_current_pve_hero!", %{user: user} do
      hero = create_base_hero()

      user = Accounts.set_current_pve_hero!(user, hero.id)

      assert user.current_pve_hero_id == hero.id
    end

    test "#set_current_pvp_hero!", %{user: user} do
      hero = create_base_hero(%{pve_battles_available: 0}, user)
      user = Accounts.get_user!(user.id)
      assert user.current_pve_hero_id

      user = Accounts.set_current_pvp_hero!(user, hero.id)

      assert user.current_pvp_hero_id == hero.id
    end

    test "#finish_pve!", %{user: user} do
      assert user.shard_limit == 100
      master = Accounts.finish_pve!(user, [], Accounts.pve_shards_for(user, 5))

      assert master.shard_limit == 50
      assert master.shard_count == 50

      diamond = Accounts.finish_pve!(master, [], Accounts.pve_shards_for(master, 4))
      assert diamond.shard_limit == 10
      assert diamond.shard_count == 90

      grandmaster = Accounts.finish_pve!(diamond, [], Accounts.pve_shards_for(diamond, 6))
      assert grandmaster.shard_limit == 0
      assert grandmaster.shard_count == 100

      diamond = Accounts.finish_pve!(grandmaster, [], Accounts.pve_shards_for(grandmaster, 4))
      assert diamond.shard_limit == 0
      assert diamond.shard_count == 100
    end
  end

  describe "#add_user_experience" do
    test "levels up when reaching max xp" do
      user = create_user()
      # MobaWeb.subscribe("user-#{user.id}")
      user = Accounts.add_user_experience(user, Moba.user_level_xp() + 100)

      assert user.level == 2
      assert user.experience == 100
      # assert user.shard_count == 1
      # assert_receive {"alert", %{level: 2, type: "battle"}}
    end
  end

  describe "#award_medals_and_shards" do
    test "first place" do
      user =
        create_user()
        |> Accounts.award_medals_and_shards(1, 6)

      assert user.medal_count == 3
      assert user.shard_count == 200
    end
  end

  describe "#user_pvp_updates!" do
    test "sets score correctly", %{user: winner} do
      loser = create_user()
      user = Accounts.user_pvp_updates!(winner.id, %{loser_user_id: loser.id})

      assert user.pvp_score["#{loser.id}"] == 1
    end

    test "sets wins/losses/points correctly", %{user: winner} do
      user = Accounts.user_pvp_updates!(winner.id, %{pvp_wins: 1, pvp_losses: 1, pvp_points: 10})

      assert user.pvp_wins == winner.pvp_wins + 1
      assert user.pvp_losses == winner.pvp_losses + 1
      assert user.pvp_points == 10
    end
  end

  describe "#user_pvp_decay!" do
    test "removes points correctly, never below 0" do
      user = create_bot(50) |> Accounts.user_pvp_decay!()
      assert user.pvp_points == 50 - Moba.pvp_round_decay()

      user = create_bot(1) |> Accounts.user_pvp_decay!()
      assert user.pvp_points == 0
    end
  end

  describe "#update_ranking" do
    test "highest medal_count is #1" do
      user = create_user(%{medal_count: 100})
      user2 = create_user(%{medal_count: 99})

      Accounts.update_ranking!()

      user = Accounts.get_user!(user.id)
      user2 = Accounts.get_user!(user2.id)

      assert user.ranking == 1
      assert user2.ranking == 2
    end
  end

  describe "messages" do
    test "#create_message" do
      MobaWeb.subscribe("chat")
      message = Accounts.create_message!(%{body: "hi"})

      assert message.body == "hi"
      assert_receive message
    end
  end

  describe "unlocks" do
    test "#create_unlock! works" do
      skill = base_skill()
      user = create_user(%{shard_count: 30}) |> Accounts.create_unlock!(skill)
      assert user.shard_count == 0
      assert user.unlocks |> List.first() |> Map.get(:resource_code) == skill.code
    end

    test "#create_unlock! not enough shards", %{user: user} do
      skill = base_skill()
      user = Accounts.create_unlock!(user, skill)
      assert user.shard_count == 0
      assert length(user.unlocks) == 0
    end

    test "#unlocked_codes_for" do
      skill = base_skill()
      user = create_user(%{shard_count: 30}) |> Accounts.create_unlock!(skill)

      assert Accounts.unlocked_codes_for(user) == [skill.code]
    end
  end
end
