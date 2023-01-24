defmodule Moba.Engine.Core.Pve do
  @moduledoc """
  Encapsulates all logic for Training battles
  """
  alias Moba.{Game, Engine}
  alias Engine.Schema.Battle

  def create_battle!(%{attacker: attacker, defender: defender, difficulty: difficulty} = _target) do
    %Battle{
      attacker: attacker,
      defender: defender,
      attacker_player: attacker.player,
      defender_player: nil,
      difficulty: difficulty,
      type: Engine.battle_types().pve
    }
    |> Engine.begin_battle!()
  end

  def finalize_battle(battle) do
    battle = manage_rewards(battle)
    attacker = Game.finalize_pve_attacker!(battle.attacker, battle.defender, battle.winner, battle.rewards)
    Engine.generate_attacker_snapshot!({battle, attacker})
  end

  # Calculates XP and gold given, all depending on battle difficulty and outcome (victory/tie/loss)
  defp manage_rewards(%{winner: winner, difficulty: difficulty, attacker: attacker} = battle) do
    total = if winner && winner.id == attacker.id, do: Moba.pve_battle_rewards(difficulty, attacker.pve_tier), else: 0

    rewards = %{
      total_xp: total,
      total_gold: total
    }

    Engine.update_battle!(battle, %{rewards: rewards})
  end
end
