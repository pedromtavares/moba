defmodule Moba.Game.LeagueRankingTest do
  use Moba.DataCase

  test "league ranking orders completed peers by farm, completion time, then id" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    hero = finished_run(now, 4, 20_000, 300)
    tie = finished_run(now, 4, 20_000, 300)
    faster = finished_run(now, 4, 20_000, 240)
    more_farm = finished_run(now, 4, 21_000, 600)
    other_league = finished_run(now, 6, 60_000, 180)
    unfinished = create_base_hero(%{league_tier: 4, total_gold_farm: 30_000})
    bot = finished_run(now, 4, 30_000, 120) |> Game.update_hero!(%{bot_difficulty: "strong"})

    result = Game.league_ranking(hero)

    assert Enum.map(result.entries, & &1.hero.id) == [more_farm.id, faster.id, hero.id, tie.id]
    assert Enum.map(result.entries, & &1.position) == [1, 2, 3, 4]
    assert result.position == 3
    assert result.total == 4
    refute Enum.any?(result.entries, &(&1.hero.id in [other_league.id, unfinished.id, bot.id]))
    assert Enum.all?(result.entries, &Ecto.assoc_loaded?(&1.hero.avatar))
    assert Enum.all?(result.entries, &Ecto.assoc_loaded?(&1.hero.skin))

    limited = Game.league_ranking(hero, 2)
    assert length(limited.entries) == 2
    assert limited.position == 3
    assert limited.total == 4
  end

  test "league standings include historical runs without the global ranking cutoff" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    old = finished_run(now, 4, 20_000, 8 * 86400)
    historical = ~U[2021-01-01 12:00:00Z]

    for tier <- 2..6 do
      hero = finished_run(historical, tier, 10_000, 300)
      result = Game.league_ranking(hero)
      assert result.position
      assert Enum.any?(result.entries, &(&1.hero.id == hero.id))
    end

    assert Game.league_ranking(old).position == 1
    current = create_base_hero(%{league_tier: 4})
    assert Game.league_ranking(current).position == nil
  end

  test "Bronze and Silver do not have league standings" do
    for tier <- 0..1 do
      hero = finished_run(DateTime.utc_now(), tier, 10_000, 300)
      assert Game.league_ranking(hero) == %{entries: [], position: nil, total: 0}
    end
  end

  test "a Gold run can finish after a failed league challenge with no turns left" do
    hero = create_base_hero(%{league_tier: 2, pve_state: "dead", pve_current_turns: 0, pve_total_turns: 0})
    finished = Game.maybe_finish_pve(hero)

    assert finished.finished_at
    assert finished.league_tier == 2
    assert Game.league_ranking(finished).position == 1
  end

  defp finished_run(now, tier, farm, duration) do
    now = DateTime.truncate(now, :second)

    create_base_hero(%{finished_at: now, league_tier: tier, total_gold_farm: farm})
    |> Ecto.Changeset.change(inserted_at: now |> DateTime.add(-duration) |> DateTime.to_naive())
    |> Moba.Repo.update!()
  end
end
