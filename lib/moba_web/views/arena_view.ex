defmodule MobaWeb.ArenaView do
  use MobaWeb, :view

  def can_battle?(attacker, defender), do: Engine.can_pvp?(attacker, defender)

  def points_for_arena_battle(attacker, defender) do
    diff = defender.pvp_points - attacker.pvp_points
    victory = Moba.attacker_win_pvp_points(diff, attacker.league_tier)
    defeat = Moba.attacker_loss_pvp_points(diff, attacker.league_tier)
    "(+#{victory}/#{defeat})"
  end

  def arena_targets_available(hero), do: Game.pvp_targets_available(hero)

  def can_switch_build?(hero), do: Game.hero_has_other_build?(hero)

  def pvp_round_progress_percentage do
    match = Game.current_match()

    if match do
      start = match.last_pvp_round_at
      ending = start |> Timex.shift(hours: Moba.pvp_round_timeout_in_hours())
      GH.time_percentage(start, ending)
    else
      0
    end
  end

  def next_round_description do
    match = Game.current_match()

    match &&
      match.last_pvp_round_at
      |> Timex.shift(hours: Moba.pvp_round_timeout_in_hours())
      |> Timex.format("{relative}", :relative)
      |> elem(1)
  end

  def can_join_grandmaster?(heroes), do: Enum.find(heroes, &(&1.league_tier == Moba.max_league_tier()))

  def has_previous_skin?(hero, selections) do
    selection = Enum.find(selections, fn selection -> selection.hero_id == hero.id end)
    selection.index > 0
  end

  def has_next_skin?(hero, selections) do
    selection = Enum.find(selections, fn selection -> selection.hero_id == hero.id end)
    length(selection.skins) > selection.index + 1
  end

  def next_skin_for(hero, selections) do
    selection = Enum.find(selections, fn selection -> selection.hero_id == hero.id end)
    next_index = selection.index + 1
    skin = Enum.at(selection.skins, next_index)
    skin.code
  end

  def previous_skin_for(hero, selections) do
    selection = Enum.find(selections, fn selection -> selection.hero_id == hero.id end)
    next_index = selection.index - 1
    skin = Enum.at(selection.skins, next_index)
    skin.code
  end
end
