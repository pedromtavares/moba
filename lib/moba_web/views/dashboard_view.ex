defmodule MobaWeb.DashboardView do
  use MobaWeb, :view

  def avatar_class(hero) do
    if hero["ranking"] && hero["total_farm"] == Moba.max_total_farm() do
      "avatar max-farm"
    else
      "avatar"
    end
  end

  def avatar_title(hero) do
    if hero["ranking"] do
      "##{hero["ranking"]} - #{hero["avatar"]["name"]}"
    else
      hero["avatar"]["name"]
    end
  end

  def can_enter_arena?(%{all_heroes: heroes}) do
    Enum.reject(heroes, &is_nil(&1.finished_at)) |> length() >= 2
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
