defmodule MobaWeb.DashboardView do
  use MobaWeb, :view

  def can_enter_arena?(%{all_heroes: heroes}) do
    Enum.reject(heroes, &is_nil(&1.finished_at)) |> length() >= 2
  end

  def farming_per_turn(pve_tier) do
    start..endd = Moba.farm_per_turn(pve_tier)

    "#{start} - #{endd}"
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

  def training_bonus_for(%{quest: %{level: 1}}), do: "+1000 starting gold (1000 -> 2000)"
  def training_bonus_for(%{quest: %{level: 4}}), do: "Ability to refresh Targets up to 5 times"
  def training_bonus_for(%{quest: %{level: 5}}), do: "Ability to refresh Targets up to 10 times"
  def training_bonus_for(%{quest: %{level: 6}}), do: "Ability to refresh Targets up to 15 times"
  def training_bonus_for(_), do: nil

  def training_difficulty_for(%{quest: %{level: 1}}), do: "3 Easy targets + 6 Medium targets"
  def training_difficulty_for(%{quest: %{level: 2}}), do: "6 Medium targets + 3 Hard targets"
  def training_difficulty_for(%{quest: %{level: 3}}), do: "3 Medium targets + 6 Hard targets"
  def training_difficulty_for(_), do: "9 Hard targets"

  def max_league_allowed_for(%{quest: %{level: 1}}), do: "Master League"
  def max_league_allowed_for(_), do: "Grandmaster League"

  def replenish_time do
    match = Game.current_match()

    match &&
      match.inserted_at
      |> Timex.shift(days: +1)
      |> Timex.format("{relative}", :relative)
      |> elem(1)
  end

  defp progression_level_sort(progressions), do: Enum.sort_by(progressions, & &1.quest.level)
end
