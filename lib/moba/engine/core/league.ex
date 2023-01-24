defmodule Moba.Engine.Core.League do
  @moduledoc """
  Encapsulates all logic for League battles - the ones fought while in a League Challenge
  """

  alias Moba.{Game, Engine}
  alias Engine.Schema.Battle

  def create_battle!(%{attacker: %{league_step: step}}, _) when step < 1 do
    {:error, "Not available"}
  end

  def create_battle!(%{attacker: attacker, defender: defender}) do
    %Battle{
      attacker: attacker,
      defender: defender,
      attacker_player: attacker.player,
      defender_player: nil,
      type: Engine.battle_types().league
    }
    |> Engine.begin_battle!()
  end

  def finalize_battle(battle) do
    battle = maybe_finalize_boss(battle)
    attacker = Game.finalize_league_attacker!(battle.attacker, battle.winner)
    Engine.generate_attacker_snapshot!({battle, attacker})
  end

  defp maybe_finalize_boss(%{attacker: %{boss_id: boss_id} = hero, defender: boss, winner: winner} = battle)
       when winner == boss and not is_nil(boss_id) do
    last_turn = List.last(battle.turns)
    boss_battler = if last_turn.attacker.hero_id == boss_id, do: last_turn.attacker, else: last_turn.defender
    attacker = Game.finalize_boss!(boss, boss_battler.current_hp, hero)
    %{battle | attacker: attacker}
  end

  defp maybe_finalize_boss(battle), do: battle
end
