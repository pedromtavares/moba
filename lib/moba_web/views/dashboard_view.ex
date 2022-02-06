defmodule MobaWeb.DashboardView do
  use MobaWeb, :view

  alias Moba.Accounts

  def achievements_in_progress(progressions) do
    incomplete_pve = filter_incompleted_by_code(progressions, "grandmaster")
    incomplete_pvp = filter_incompleted_by_code(progressions, "arena")

    Enum.sort_by(filter_by_level(incomplete_pvp) ++ filter_by_level(incomplete_pve), & &1.quest.shard_prize)
  end

  def achievements_completed(progressions) do
    Enum.filter(progressions, & &1.completed_at) |> Enum.sort_by(& &1.quest.shard_prize)
  end

  def farming_per_turn(pve_tier) do
    start..endd = Moba.farm_per_turn(pve_tier)

    "#{start} - #{endd}"
  end

  def next_medal_percentage(%{season_tier: current_tier, season_points: season_points}) do
    max = Accounts.season_points_for(current_tier + 1)
    season_points * 100 / max
  end

  def next_medal(%{season_tier: current_tier}) do
    cond do
      current_tier >= Moba.max_season_tier() -> nil
      true -> current_tier + 1
    end
  end

  def next_pve_tier(%{pve_tier: current_tier}) do
    cond do
      current_tier >= Moba.max_season_tier() -> nil
      true -> current_tier + 1
    end
  end

  def has_active_season_progression?(progressions) do
    Game.active_quest_progression?(progressions)
  end

  def max_season_progression_level(progressions) do
    last = Game.active_quest_progression?(progressions)
    if last.quest.level >= 3, do: 4, else: last.quest.level + 1
  end

  def progression_percentage(%{quest: quest} = progression) do
    total = quest.final_value

    progression.current_value * 100 / total
  end

  def pve_daily_progressions(progressions) do
    progressions
    |> Enum.filter(&Enum.member?(["daily_master", "daily_perfect", "daily_grandmaster"], &1.quest.code))
    |> progression_level_sort()
  end

  def jungle_bonus_for(%{quest: %{level: 1}}), do: "+1000 starting gold (1000 -> 2000)"
  def jungle_bonus_for(%{quest: %{level: 3}}), do: "Used turn is reimbursed upon death"
  def jungle_bonus_for(%{quest: %{level: 4}}), do: "Ability to refresh Targets up to 5 times"
  def jungle_bonus_for(_), do: nil

  def jungle_difficulty_for(%{quest: %{level: 1}}), do: "3 Easy targets + 6 Medium targets"
  def jungle_difficulty_for(%{quest: %{level: 2}}), do: "6 Medium targets + 3 Hard targets"
  def jungle_difficulty_for(%{quest: %{level: 3}}), do: "3 Medium targets + 6 Hard targets"
  def jungle_difficulty_for(_), do: "9 Hard targets"

  def max_league_allowed_for(%{quest: %{level: 1}}), do: "Master League"
  def max_league_allowed_for(_), do: "Grandmaster League"

  defp filter_incompleted_by_code(progressions, code) do
    progressions
    |> Enum.filter(&is_nil(&1.completed_at))
    |> Enum.filter(&String.starts_with?(&1.quest.code, code))
  end

  defp filter_by_level(progressions) do
    lowest_level_progression = progressions |> Enum.sort_by(& &1.quest.level) |> List.first()

    Enum.filter(progressions, &(&1.quest.level <= lowest_level_progression.quest.level))
  end

  defp progression_level_sort(progressions), do: Enum.sort_by(progressions, & &1.quest.level)
end
