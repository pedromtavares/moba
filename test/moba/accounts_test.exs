defmodule Moba.AccountsTest do
  use Moba.DataCase, async: true

  setup do
    %{user: create_user()}
  end

  describe "user updates" do
    test "#set_user_online_now", %{user: user} do
      {1, nil} = Accounts.set_online_now(user)
      user = Accounts.get_user!(user.id)

      assert user.last_online_at
    end
  end

  describe "messages" do
    test "#create_message" do
      MobaWeb.subscribe("community")
      message = Accounts.create_message!(%{body: "hi", channel: "community"})

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
