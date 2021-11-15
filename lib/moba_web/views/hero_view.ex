defmodule MobaWeb.HeroView do
  use MobaWeb, :view

  def finished_jungle?(user, hero) do
    if user.current_pve_hero_id do
      current_hero = Game.get_hero!(user.current_pve_hero_id)
      current_hero.finished_pve && hero == current_hero && hero
    end
  end

  def can_join_arena?(user), do: length(Game.eligible_heroes_for_pvp(user.id)) > 0

  def quest_title_for(progressions) when length(progressions) > 1, do: "Quests"
  def quest_title_for(_), do: "Quest"

  def history_avatars(%{history_codes: history_codes}, avatars) do
    Enum.filter(avatars, &(&1.code in history_codes))
  end

  def next_match_description, do: MobaWeb.CurrentHeroView.next_match_description()

  def tier_class(tier, hero_tier) do
    cond do
      tier == hero_tier -> "current-tier"
      tier > hero_tier -> "next-tier"
      true -> "previous-tier"
    end
  end
end
