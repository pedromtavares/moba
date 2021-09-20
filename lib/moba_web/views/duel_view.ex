defmodule MobaWeb.DuelView do
  use MobaWeb, :view

  def can_switch_build?(hero), do: Game.hero_has_other_build?(hero)
  def phase_class(%{phase: phase}, current_phase) when phase == current_phase, do: "active"
  def phase_class(_, _), do: ""
end
