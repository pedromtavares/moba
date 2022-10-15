defmodule Moba.Engine.Core.Match do
  @moduledoc """
  Encapsulates all logic for Match battles
  """

  alias Moba.Engine
  alias Engine.Schema.Battle

  def create_battle!(%{attacker: attacker} = attrs) do
    attacker_initial_hp = Map.get(attacker, :initial_hp)
    attacker_initial_mp = Map.get(attacker, :initial_mp)

    if valid?(attrs) do
      battle_for(attrs)
      |> Engine.begin_battle!(%{attacker_initial_hp: attacker_initial_hp, attacker_initial_mp: attacker_initial_mp})
    else
      {:error, "Invalid target"}
    end
  end

  def valid?(%{attacker: %{id: attacker_id}, defender: %{id: defender_id}}) when attacker_id == defender_id, do: false
  def valid?(_), do: true

  def finalize_battle(battle) do
    battle
    |> generate_snapshots()
  end

  defp battle_for(%{attacker: attacker, defender: defender, match: match}) do
    %Battle{
      attacker: attacker,
      defender: defender,
      match_id: match.id,
      type: Engine.battle_types().match,
      match: match
    }
  end

  defp generate_snapshots(%{attacker: attacker, defender: defender} = battle) do
    tuple = {battle, attacker, defender}
    Engine.generate_attacker_snapshot!(tuple) && Engine.generate_defender_snapshot!(tuple)
    battle
  end
end
