defmodule MobaWeb.HeroView do
  use MobaWeb, :view

  def just_finished_training?(_, %{finished_at: nil}), do: nil

  def just_finished_training?(player, %{finished_at: finished_at} = hero) do
    ago = Timex.now() |> Timex.shift(days: -1)
    diff = Timex.diff(finished_at, ago)

    if player.current_pve_hero_id && diff > 0 do
      current_hero = Game.get_hero!(player.current_pve_hero_id)
      current_hero.finished_at && hero.id == current_hero.id && hero
    end
  end

  def in_ranking?(ranking, %{id: id}) do
    ranking
    |> Enum.map(& &1.id)
    |> Enum.member?(id)
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
