defmodule Moba.Game.Leagues do
  @moduledoc """
  Manages gameplay logic related to the League Challenge.
  More information on Moba.Engine.Core.League
  """

  alias Moba.{Repo, Game}
  alias Game.Query.HeroQuery

  @master_league_tier Moba.master_league_tier()

  # -------------------------------- PUBLIC API

  def max_step_for(tier) do
    case tier do
      0 -> 2
      1 -> 3
      2 -> 4
      3 -> 5
      4 -> 5
      _ -> 1
    end
  end

  @doc """
  When in a League Challenge, the attacker faces consecutive defenders in order to rank up.
  These defenders get stronger with higher levels and difficulty as the challenge progresses
  """
  def defender_for(%{league_tier: tier} = attacker) when tier == @master_league_tier, do: boss_defender(attacker)

  def defender_for(%{league_step: step} = attacker) do
    case step do
      0 -> easiest_defender(attacker)
      1 -> easy_defender(attacker)
      2 -> moderate_defender(attacker)
      3 -> moderate_defender(attacker)
      4 -> hard_defender(attacker)
      5 -> hardest_defender(attacker)
    end
  end

  def tier_for(level) when level >= 25, do: 5

  def tier_for(level) do
    Enum.find(0..5, fn tier -> base_level(tier) + 3 > level end) || 0
  end

  # --------------------------------

  defp get_first(query) do
    query |> Repo.all() |> List.first()
  end

  defp easiest_defender(%{id: id, league_tier: league_tier}) do
    HeroQuery.league_defender(id, base_level(league_tier), "weak")
    |> get_first()
  end

  defp easy_defender(%{id: id, league_tier: league_tier}) do
    HeroQuery.league_defender(id, base_level(league_tier) + 1, "weak")
    |> get_first()
  end

  defp moderate_defender(%{id: id, league_tier: league_tier}) do
    HeroQuery.league_defender(id, base_level(league_tier) + 2, "moderate")
    |> get_first()
  end

  defp hard_defender(%{id: id, league_tier: league_tier}) do
    HeroQuery.league_defender(id, base_level(league_tier) + 3, "moderate")
    |> get_first()
  end

  defp hardest_defender(%{id: id, league_tier: league_tier}) do
    HeroQuery.league_defender(id, base_level(league_tier) + 3, "strong")
    |> get_first()
  end

  defp boss_defender(%{boss_id: boss_id}), do: Game.get_hero!(boss_id)

  defp base_level(tier) do
    case tier do
      0 -> 7
      1 -> 11
      2 -> 15
      3 -> 18
      4 -> 22
      5 -> 25
    end
  end
end
