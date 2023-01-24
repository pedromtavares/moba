defmodule Moba.Engine.Core.Match do
  @moduledoc """
  Encapsulates all logic for Match battles
  """

  alias Moba.Engine
  alias Engine.Schema.Battle

  def create_battle!(%{attacker: attacker} = attrs) do
    attacker_initial_hp = Map.get(attacker, :initial_hp)
    attacker_initial_mp = Map.get(attacker, :initial_mp)

    Engine.begin_battle!(battle_for(attrs), %{
      attacker_initial_hp: attacker_initial_hp,
      attacker_initial_mp: attacker_initial_mp
    })
  end

  def finalize_battle(battle) do
    battle
    |> generate_snapshots()
  end

  defp battle_for(battle) do
    %{attacker: attacker, attacker_player: aplayer, defender: defender, defender_player: dplayer, match: match} = battle

    %Battle{
      attacker: attacker,
      defender: defender,
      attacker_player: aplayer,
      defender_player: dplayer,
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
