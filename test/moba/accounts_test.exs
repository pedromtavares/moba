defmodule Moba.AccountsTest do
  use Moba.DataCase, async: true

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
      hero = create_base_hero(%{pve_current_turns: 0}, user)
      user = Accounts.get_user!(user.id)
      assert user.current_pve_hero_id

      user = Accounts.set_current_pvp_hero!(user, hero.id)

      assert user.current_pvp_hero_id == hero.id
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

  describe "#user_duel_updates!" do
    test "sets score correctly", %{user: winner} do
      loser = create_user()
      user = Accounts.user_duel_updates!(winner, %{loser_id: loser.id})

      assert user.duel_score["#{loser.id}"] == 1
    end

    test "sets wins/losses/points correctly", %{user: winner} do
      user = Accounts.user_duel_updates!(winner, %{duel_winner: winner, pvp_points: 10})

      assert user.duel_wins == winner.duel_wins + 1
      assert user.duel_count == winner.duel_count + 1
    end
  end

  describe "messages" do
    test "#create_message" do
      MobaWeb.subscribe("chat")
      message = Accounts.create_message!(%{body: "hi"})

      assert message.body == "hi"
      assert_receive _message
    end
  end

  describe "unlocks" do
    test "#create_unlock! works" do
      skill = base_skill()
      user = create_user(%{shard_count: 100}) |> Accounts.create_unlock!(skill)
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
      user = create_user(%{shard_count: 100}) |> Accounts.create_unlock!(skill)

      assert Accounts.unlocked_codes_for(user) == [skill.code]
    end
  end
end
