defmodule Moba.Content.SeedSetupTest do
  use Moba.DataCase

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
