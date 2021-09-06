defmodule MobaWeb.HeroView do
  use MobaWeb, :view

  def finished_jungle?(user, hero) do
    if user.current_pve_hero_id do
      current_hero = Game.get_hero!(user.current_pve_hero_id)
      current_hero.finished_pve && hero == current_hero && hero
    end
  end

  def can_join_arena?(user), do: length(Game.eligible_heroes_for_pvp(user.id)) > 0

  def next_match_description, do: MobaWeb.CurrentHeroView.next_match_description()

  def tier_class(tier, hero_tier) do
    cond do
      tier == hero_tier -> "current-tier"
      tier > hero_tier -> "next-tier"
      true -> "previous-tier"
    end
  end
end
