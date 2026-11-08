defmodule Moba.Game.Leagues do
  @moduledoc """
  Manages gameplay logic related to the League Challenge.
  More information on Moba.Engine.Core.League
  """

  alias Moba.{Repo, Game}
  alias Game.Query.HeroQuery

  @master_league_tier Moba.master_league_tier()

  # -------------------------------- PUBLIC API

  @doc """
  When in a League Challenge, the attacker faces consecutive defenders in order to rank up.
  These defenders get stronger with higher levels and difficulty as the challenge progresses
  """
  def league_defender_for(%{league_tier: tier} = attacker) when tier == @master_league_tier, do: boss_defender(attacker)

  def league_defender_for(%{id: id, league_tier: tier, league_step: step}) do
    {level, difficulty} = defender_profile(tier, step)
    defender_for_level(id, level, difficulty)
  end

  def defender_for_level(attacker_id, level, difficulty),
    do: HeroQuery.league_defender(attacker_id, level, difficulty) |> Repo.one()

  def defender_profile(tier, step) do
    level = base_level(tier)

    case step do
      0 -> {level, "moderate"}
      1 -> {level + 1, "moderate"}
      step when step in [2, 3] -> {level + 2, "moderate"}
      4 -> {level + 3, "moderate"}
      5 -> {level + 3, "strong"}
    end
  end

  def max_league_step_for(tier) do
    case tier do
      0 -> 2
      1 -> 3
      2 -> 4
      3 -> 5
      4 -> 5
      _ -> 1
    end
  end

  def league_tier_for(level) when level >= 25, do: 6

  def league_tier_for(level) do
    Enum.find(0..5, fn tier -> base_level(tier) + 3 > level end) || 0
  end

  def league_level_range_for(tier), do: base_level(tier)..(base_level(tier) + 3)

  # --------------------------------

  defp boss_defender(%{boss_id: boss_id}), do: Game.get_hero!(boss_id)

  defp base_level(tier) do
    case tier do
      0 -> 3
      1 -> 6
      2 -> 9
      3 -> 13
      4 -> 17
      5 -> 22
      6 -> 24
    end
  end
end
