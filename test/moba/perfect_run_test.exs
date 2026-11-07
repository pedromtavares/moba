defmodule Moba.Game.Training.PerfectRunTest do
  use ExUnit.Case, async: true
  alias Moba.Game.Training.PerfectRun

  defp hero(attrs \\ %{}) do
    Map.merge(
      %{
        total_xp_farm: 0,
        total_gold_farm: 0,
        league_tier: 0,
        pve_tier: 2,
        pve_current_turns: 5,
        pve_total_turns: 25,
        finished_at: nil
      },
      attrs
    )
  end

  defp team(attrs \\ %{}) do
    Map.merge(
      %{
        heroes: Map.new(1..3, &{&1, %{hero: hero()}}),
        goal: 6,
        league_tier: 0,
        turns_left: 5,
        reserve_turns: 25,
        phase: :playing
      },
      attrs
    )
  end

  test "refunded target deaths preserve eligibility; spending farm or taking smaller rewards does not" do
    run = hero(%{pve_current_turns: 4, total_xp_farm: 600, total_gold_farm: 600, losses: 1, pve_state: "dead"})
    assert PerfectRun.solo?(run)
    refute PerfectRun.solo?(%{run | total_gold_farm: 500})
    refute PerfectRun.solo?(%{run | total_xp_farm: 500, total_gold_farm: 500})
    assert PerfectRun.solo?(hero())
    assert PerfectRun.team?(team())
  end

  test "lower league caps and failed league challenges cannot promise a Perfect run" do
    refute PerfectRun.solo?(hero(%{pve_tier: 0}))
    refute PerfectRun.solo?(hero(%{pve_tier: 1}))

    refute PerfectRun.solo?(
             hero(%{pve_current_turns: 5, pve_total_turns: 20, total_xp_farm: 3000, total_gold_farm: 3000})
           )

    refute PerfectRun.team?(team(%{goal: 4}))
    refute PerfectRun.team?(team(%{reserve_turns: 20}))
  end

  test "an in-flight target does not temporarily remove the indicator" do
    run = hero(%{pve_current_turns: 4})
    refute PerfectRun.solo?(run)
    assert PerfectRun.solo?(run, true)
    run = team(%{phase: :engagement, turns_left: 4, encounters: [%{kind: :farm}]})
    assert PerfectRun.team?(run)
  end

  test "Focus eligibility uses the whole team's farm, not an individual carry" do
    run = team(%{league_tier: 6, turns_left: 0, reserve_turns: 0, phase: :finished})

    heroes =
      Map.new([{1, 37_700}, {2, 30_000}, {3, 22_300}], fn {id, xp} ->
        {id, %{hero: hero(%{total_gold_farm: 30_000, total_xp_farm: xp})}}
      end)

    assert PerfectRun.team?(%{run | heroes: heroes})
    refute PerfectRun.team?(put_in(%{run | heroes: heroes}.heroes[3].hero.total_gold_farm, 29_990))
    assert PerfectRun.completed_team?(%{league_tier: 6, total_farm: 180_000})
    refute PerfectRun.completed_team?(%{league_tier: 6, total_farm: 179_990})
    refute PerfectRun.completed_team?(%{league_tier: 5, total_farm: 180_000})
  end

  test "finished solo runs require both Grandmaster and full farm" do
    run = hero(%{finished_at: ~U[2026-11-06 00:00:00Z], league_tier: 6, total_xp_farm: 30_000, total_gold_farm: 30_000})
    assert PerfectRun.solo?(run)
    refute PerfectRun.solo?(%{run | total_gold_farm: 29_900})
    refute PerfectRun.solo?(%{run | league_tier: 5})
  end
end
