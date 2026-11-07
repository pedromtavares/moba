defmodule Moba.Game.Training.PerfectRun do
  @moduledoc "Whether a training run can still earn the full Grandmaster farm budget."

  def farm(hero), do: hero.total_xp_farm + hero.total_gold_farm

  def solo?(hero, pending_target? \\ false) do
    remaining = hero.pve_current_turns + hero.pve_total_turns + if(pending_target?, do: 1, else: 0)

    qualifies?(
      farm(hero),
      hero.league_tier,
      Moba.max_available_league(hero.pve_tier),
      remaining,
      hero.pve_total_turns,
      1,
      not is_nil(hero.finished_at)
    )
  end

  def team?(run) do
    farm = Enum.sum(Enum.map(run.heroes, fn {_, h} -> farm(h.hero) end))
    encounter = Moba.Game.TeamTraining.active_encounter(run)
    pending_turn = if encounter && encounter.kind == :farm, do: 1, else: 0

    qualifies?(
      farm,
      run.league_tier,
      run.goal,
      run.turns_left + run.reserve_turns + pending_turn,
      run.reserve_turns,
      3,
      run.phase == :finished
    )
  end

  def completed_team?(%{league_tier: tier, total_farm: farm}) when is_integer(farm),
    do: tier == Moba.max_league_tier() && farm >= 3 * Moba.max_total_farm()

  def completed_team?(_), do: false

  defp qualifies?(farm, tier, goal, remaining_turns, reserve, size, finished?) do
    grandmaster = Moba.max_league_tier()
    remaining_leagues = max(0, Moba.master_league_tier() - tier)
    bonus = remaining_leagues * Moba.league_win_bonus() + if(tier < grandmaster, do: Moba.boss_win_bonus(), else: 0)
    maximum = farm + size * 2 * (remaining_turns * Moba.pve_battle_rewards("strong", 2) + bonus)

    cond do
      finished? -> tier == grandmaster && farm >= size * Moba.max_total_farm()
      goal < grandmaster -> false
      tier + 1 + div(reserve, Moba.turns_per_tier()) < grandmaster -> false
      true -> maximum >= size * Moba.max_total_farm()
    end
  end
end
