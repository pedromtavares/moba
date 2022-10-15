defmodule MobaWeb.MatchView do
  use MobaWeb, :view

  def player_pick(%{attacker_id: aid, defender_id: did}, %{player_picks: picks}) do
    Enum.find(picks, &(&1.id == aid || &1.id == did))
  end

  def opponent_pick(%{attacker_id: aid, defender_id: did}, %{opponent_picks: picks}) do
    Enum.find(picks, &(&1.id == aid || &1.id == did))
  end
end
