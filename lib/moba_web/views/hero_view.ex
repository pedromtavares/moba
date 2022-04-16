defmodule MobaWeb.HeroView do
  use MobaWeb, :view

  def just_finished_training?(_, %{finished_at: nil}), do: nil

  def just_finished_training?(user, %{finished_at: finished_at} = hero) do
    ago = Timex.now() |> Timex.shift(days: -1)
    diff = Timex.diff(finished_at, ago)

    if user.current_pve_hero_id && diff > 0 do
      current_hero = Game.get_hero!(user.current_pve_hero_id)
      current_hero.finished_at && hero.id == current_hero.id && hero
    end
  end

  def display_quest_tabs?(%{
        completed_progressions: all,
        completed_daily_progressions: daily,
        completed_season_progression: season
      }) do
    length(all) > 1 && all != daily && all != season
  end

  def quest_title_for(progressions) when length(progressions) > 1, do: "Quests"
  def quest_title_for(_), do: "Quest"

  def history_avatars(%{history_codes: history_codes}, avatars) do
    Enum.filter(avatars, &(&1.code in history_codes))
  end

  def tier_class(tier, hero_tier) do
    cond do
      tier == hero_tier -> "current-tier"
      tier > hero_tier -> "next-tier"
      true -> "previous-tier"
    end
  end

  def has_previous_skin?(selection) do
    selection.index > 0
  end

  def has_next_skin?(selection) do
    length(selection.skins) > selection.index + 1
  end

  def next_skin_for(selection) do
    next_index = selection.index + 1
    skin = Enum.at(selection.skins, next_index)
    skin.code
  end

  def previous_skin_for(selection) do
    next_index = selection.index - 1
    skin = Enum.at(selection.skins, next_index)
    skin.code
  end
end
