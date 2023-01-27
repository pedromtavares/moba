defmodule MobaWeb.DashboardView do
  use MobaWeb, :view

  def avatar_class(hero) do
    if hero["total_farm"] == Moba.max_total_farm() do
      "avatar max-farm"
    else
      "avatar"
    end
  end

  def avatar_title(hero) do
    hero["avatar"]["name"]
  end

  def can_delete?(hero) do
    is_nil(hero.pve_ranking) ||
      hero.league_tier < Moba.max_league_tier() ||
      is_nil(hero.finished_at) ||
      not Game.available_hero?(hero)
  end

  def farming_per_turn(pve_tier) do
    start..endd = Moba.farm_per_turn(pve_tier)

    "#{start} - #{endd}"
  end

  def next_pve_tier(%{pve_tier: current_tier}) do
    cond do
      current_tier >= Moba.max_pve_tier() -> nil
      true -> current_tier + 1
    end
  end

  def current_quest_avatars(%{pve_tier: tier, pve_progression: progression}) do
    codes =
      case tier do
        4 -> progression.master_codes
        5 -> progression.grandmaster_codes
        6 -> progression.invoker_codes
        _ -> progression.season_codes
      end

    Enum.map(codes, &Moba.load_resource(&1)) |> Enum.map(& &1.name) |> Enum.join(", ")
  end

  def current_quest_description(%{pve_tier: tier}) do
    Game.get_quest(tier + 1).description
  end

  def current_quest_progression_label(%{pve_tier: tier, pve_progression: progression}) do
    quest = Game.get_quest(tier + 1)
    current_count = Map.get(progression, quest.field) |> length()
    "#{current_count}/#{quest.goal} Avatars"
  end

  def current_quest_progression_percentage(%{pve_tier: tier, pve_progression: progression}) do
    quest = Game.get_quest(tier + 1)
    current_count = Map.get(progression, quest.field) |> length()
    current_count * 100 / quest.goal
  end

  def quest_shard_prize(tier), do: Game.get_quest(tier).prize

  def training_bonus_for(tier), do: Map.get(Game.get_quest(tier), :training_bonus)

  def training_difficulty_for(tier), do: Map.get(Game.get_quest(tier), :difficulty) || Game.get_quest(7).difficulty

  def max_league_allowed_for(tier), do: Map.get(Game.get_quest(tier), :max_league) || Game.get_quest(7).max_league
end
