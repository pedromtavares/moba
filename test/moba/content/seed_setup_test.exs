defmodule Moba.Content.SeedSetupTest do
  use Moba.DataCase

  test "every playable hero has training opponents across all levels and difficulties" do
    avatars = Game.Query.AvatarQuery.base_canon() |> Repo.all()

    coverage =
      from(h in Game.Schema.Hero,
        where: is_nil(h.archived_at) and not is_nil(h.bot_difficulty),
        select: {h.avatar_id, h.level, h.bot_difficulty},
        distinct: true
      )
      |> Repo.all()
      |> MapSet.new()

    for avatar <- avatars, level <- 0..35 do
      difficulties = if level == 0, do: ["weak", "moderate"], else: ["weak", "moderate", "strong"]

      for difficulty <- difficulties do
        assert MapSet.member?(coverage, {avatar.id, level, difficulty}),
               "Missing #{difficulty} #{avatar.code} opponent at level #{level}"
      end
    end
  end

  test "each playable hero has equipped Master and Grandmaster fallback builds" do
    for avatar <- Game.Query.AvatarQuery.base_canon() |> Repo.all(),
        {difficulty, level, tier} <- [{"pvp_master", 24, 5}, {"pvp_grandmaster", 26, 6}] do
      bots =
        from(h in Game.Schema.Hero,
          where: h.avatar_id == ^avatar.id and h.bot_difficulty == ^difficulty and is_nil(h.archived_at),
          preload: [:skills, :items]
        )
        |> Repo.all()

      assert length(bots) >= 5, "Not enough #{difficulty} fallback heroes for #{avatar.code}"

      for bot <- bots do
        assert bot.level == level
        assert bot.league_tier == tier
        assert length(bot.skills) == 4
        assert Enum.any?(bot.skills, &(&1.code == avatar.ultimate_code and &1.ultimate))
        assert bot.items != []
        assert length(bot.items) <= 6
        assert bot.total_hp > avatar.total_hp
        assert bot.atk > avatar.atk
      end
    end
  end

  test "seeded opponents cover every step of every non-boss league" do
    for tier <- 0..(Moba.master_league_tier() - 1),
        step <- 0..(Game.max_league_step_for(tier) - 1) do
      defender = Game.Leagues.league_defender_for(%{id: -1, league_tier: tier, league_step: step})
      assert match?(%Game.Schema.Hero{}, defender), "Missing seeded opponent for league #{tier}, step #{step}"
    end
  end

  test "admin match statistics render a fresh game with no scored matches" do
    Repo.update_all(Game.Schema.Match, set: [phase: "pending"])

    for {_bracket, stats} <- Admin.match_stats() do
      assert stats.total == 0
      assert stats.winrate == 0.0
      assert stats.avatars == %{}
      assert stats.skills == %{}
      assert stats.items == %{}
    end
  end
end
