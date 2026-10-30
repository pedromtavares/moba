defmodule Moba.Game.QuestsTest do
  use Moba.DataCase, async: true

  setup do
    # The test database still has the original roster; simulate the four additions.
    attrs = Map.take(base_avatar(), [:atk, :total_hp, :total_mp, :power, :armor, :speed])

    for number <- 1..4 do
      Game.create_avatar!(
        %Game.Schema.Avatar{enabled: true, current: false, ultimate_code: "coup"},
        Map.merge(attrs, %{code: "expansion_#{number}", name: "Expansion #{number}"})
      )
    end

    :ok
  end

  for {tier, field, league, farm} <- [
        {5, :master_codes, 5, 0},
        {6, :grandmaster_codes, 6, 0},
        {7, :invoker_codes, 6, Moba.max_total_farm()}
      ] do
    @tier tier
    @field field
    @league league
    @farm farm

    test "#{Moba.pve_tiers()[tier]} requires 20 distinct qualifying Avatars even with a larger roster" do
      avatars = Game.list_avatars()
      assert length(avatars) > 20
      codes = Enum.map(avatars, & &1.code)
      quest = Game.get_quest(@tier)
      assert quest.goal == 20

      player = create_player!(%{pve_tier: @tier - 1, pve_progression: %{@field => Enum.take(codes, 18)}})

      hero = %{
        player: player,
        avatar: Enum.at(avatars, 18),
        league_tier: @league,
        total_xp_farm: @farm,
        total_gold_farm: 0
      }

      Game.Quests.track_pve_progression!(hero)
      player = Game.get_player!(player.id)
      assert player.pve_tier == @tier - 1
      assert length(Map.get(player.pve_progression, @field)) == 19

      # Repeating the same Avatar must not count as a twentieth completion.
      Game.Quests.track_pve_progression!(%{hero | player: player})
      player = Game.get_player!(player.id)
      assert player.pve_tier == @tier - 1
      assert length(Map.get(player.pve_progression, @field)) == 19

      Game.Quests.track_pve_progression!(%{hero | player: player, avatar: Enum.at(avatars, 19)})
      updated = Game.get_player!(player.id)
      assert updated.pve_tier == @tier
      assert length(Map.get(updated.pve_progression, @field)) == 20
      assert updated.user.shard_count == player.user.shard_count + quest.prize
      assert Map.has_key?(updated.pve_progression.history, to_string(@tier))
    end
  end

  test "a new Avatar must satisfy the rank's league and farm conditions" do
    for {tier, field, league, farm} <- [
          {5, :master_codes, 4, Moba.max_total_farm()},
          {6, :grandmaster_codes, 5, Moba.max_total_farm()},
          {7, :invoker_codes, 5, Moba.max_total_farm()},
          {7, :invoker_codes, 6, Moba.max_total_farm() - 1}
        ] do
      avatars = Game.list_avatars()
      codes = avatars |> Enum.take(19) |> Enum.map(& &1.code)
      player = create_player!(%{pve_tier: tier - 1, pve_progression: %{field => codes}})
      player = Game.get_player!(player.id)

      Game.Quests.track_pve_progression!(%{
        player: player,
        avatar: Enum.at(avatars, 19),
        league_tier: league,
        total_xp_farm: farm,
        total_gold_farm: 0
      })

      updated = Game.get_player!(player.id)
      assert updated.pve_tier == tier - 1
      assert Map.get(updated.pve_progression, field) == codes
      assert updated.user.shard_count == player.user.shard_count
    end
  end
end
