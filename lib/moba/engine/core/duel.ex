defmodule Moba.Engine.Core.Duel do
  @moduledoc """
  Encapsulates all logic for Duel battles
  """

  alias Moba.{Game, Engine}
  alias Engine.Schema.Battle

  def create_battle!(attrs) do
    if valid?(attrs) do
      battle_for(attrs)
      |> Engine.begin_battle!()
    else
      {:error, "Invalid target"}
    end
  end

  def finalize_battle(battle) do
    battle
    |> generate_snapshots()
  end

  defp battle_for(%{attacker: attacker, defender: defender, duel_id: duel_id}) do
    %Battle{
      attacker: attacker,
      defender: defender,
      duel_id: duel_id,
      type: Engine.battle_types().duel,
      duel: Game.get_duel!(duel_id)
    }
  end

  defp generate_snapshots(battle) do
    battle = Engine.generate_attacker_snapshot!({battle, battle.attacker, battle.defender})
    Engine.generate_defender_snapshot!({battle, battle.attacker, battle.defender})
  end

  defp valid?(%{attacker: %{id: attacker_id}, defender: %{id: defender_id}}) when attacker_id == defender_id, do: false
  defp valid?(_), do: true
end
