defmodule MobaWeb.DuelView do
  use MobaWeb, :view

  def phase_class(%{phase: phase}, current_phase) when phase == current_phase, do: "active"
  def phase_class(_, _), do: ""

  def finished?(%{phase: "finished"}), do: true
  def finished?(_), do: false
end
