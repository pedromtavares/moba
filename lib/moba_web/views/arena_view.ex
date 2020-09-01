defmodule MobaWeb.ArenaView do
  use MobaWeb, :view

  alias Moba.{Game, Engine}
  alias MobaWeb.{GameView, HeroView}

  def can_battle?(attacker, defender), do: Engine.can_pvp?(attacker, defender)

  def next_match_description, do: HeroView.next_match_description()

  def points_for_arena_battle(attacker, defender) do
    diff = defender.pvp_points - attacker.pvp_points
    victory = Moba.attacker_win_pvp_points(diff)
    defeat = Moba.attacker_loss_pvp_points(diff)
    "(+#{victory}/#{defeat})"
  end

  def arena_targets_available(hero), do: Game.pvp_targets_available(hero)

  def can_switch_build?(hero), do: Game.hero_has_other_build?(hero)

  def pvp_round_progress_percentage do
    match = Game.current_match()

    if match do
      start = match.last_pvp_round_at
      ending = start |> Timex.shift(hours: Moba.pvp_round_timeout_in_hours())
      HeroView.time_percentage(start, ending)
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
end
