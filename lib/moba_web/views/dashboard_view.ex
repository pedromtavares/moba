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

  def rewards_for(ranking) do
    number = round(3 / ranking)

    medals =
      Enum.reduce(1..number, "", fn _n, acc ->
        acc <> "<i class='fa fa-medal'></i>"
      end)

    raw(medals)
  end

  def shards_for(ranking, league_tier) do
    number = round(3 / ranking)
    total = 50 + number * 50

    if league_tier == Moba.max_league_tier() do
      total
    else
      div(total, 2)
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

  def pvp_daily_progressions(progressions) do
    progressions
    |> Enum.filter(&String.starts_with?(&1.quest.code, "daily_arena"))
    |> progression_level_sort()
  end

  def jungle_bonus_for(%{quest: %{level: 1}}), do: "+1000 starting gold (1000 -> 2000)"
  def jungle_bonus_for(%{quest: %{level: 2}}), do: "50% gold discount on Buybacks"
  def jungle_bonus_for(%{quest: %{level: 3}}), do: "Gank is reimbursed on death (+1 available Ganks)"
  def jungle_bonus_for(%{quest: %{level: 4}}), do: "Ability to refresh Targets up to 5 times"

  def pve_tab_header(current_pve_tab, tab, class, do: block) when current_pve_tab == tab do
    content_tag(:div, [class: "pve-header #{class} bg-secondary active"], do: block)
  end

  def pve_tab_header(_, tab, class, do: block) do
    content_tag(:div, [class: "pve-header #{class} bg-light link", "phx-click": "pve-tab", "phx-value-tab": tab],
      do: block
    )
  end

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
