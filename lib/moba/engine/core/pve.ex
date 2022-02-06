defmodule Moba.Engine.Core.Pve do
  @moduledoc """
  Encapsulates all logic for PVE battles - the ones fought in the Jungle
  """
  alias Moba.{Game, Engine}
  alias Engine.Schema.Battle

  def create_battle!(%{attacker: %{pve_current_turns: turns}}) when turns < 1 do
    {:error, "Not enough available turns"}
  end

  def create_battle!(target) do
    target
    |> battle_for()
    |> Engine.start_battle!()
    |> manage_current_turns()
    |> update_attacker()
    |> generate_targets()
  end

  def finalize_battle(battle) do
    battle
    |> manage_rewards()
    |> manage_score()
    |> manage_updates()
    |> update_attacker()
    |> maybe_generate_boss()
    |> maybe_finish_pve()
    |> Engine.generate_attacker_snapshot!()
  end

  defp battle_for(%{attacker: attacker, defender: defender, difficulty: difficulty}) do
    %Battle{
      attacker: attacker,
      defender: defender,
      difficulty: difficulty,
      match_id: attacker.match_id,
      type: Engine.battle_types().pve
    }
  end

  defp manage_current_turns(%{attacker: attacker} = battle) do
    updates = %{pve_current_turns: attacker.pve_current_turns - 1}
    {battle, updates}
  end

  defp update_attacker({battle, updates}) do
    attacker = Game.update_attacker!(battle.attacker, updates)
    battle = Map.put(battle, :attacker, attacker)

    {battle, attacker}
  end

  defp generate_targets({battle, attacker}) do
    Game.generate_targets!(attacker)

    battle
  end

  defp maybe_generate_boss({battle, attacker}) do
    attacker = Game.maybe_generate_boss(attacker)

    {battle, attacker}
  end

  defp maybe_finish_pve({battle, attacker}) do
    attacker = Game.maybe_finish_pve(attacker)

    {battle, attacker}
  end

  # Calculates XP and gold given, all depending on battle difficulty and outcome (victory/tie/loss)
  defp manage_rewards(%{winner: winner, difficulty: difficulty, attacker: attacker} = battle) do
    base_battle_xp = Moba.battle_xp(difficulty, attacker.pve_tier)
    win_bonus = Moba.pve_win_bonus()

    win = winner && attacker.id == winner.id
    alive = win || is_nil(winner)

    battle_xp = (alive && base_battle_xp) || 0

    win_xp = (win && win_bonus) || 0

    total = battle_xp + win_xp

    rewards = %{
      battle_xp: battle_xp,
      win_xp: win_xp,
      total_xp: total,
      total_gold: total
    }

    Engine.update_battle!(battle, %{rewards: rewards})
  end

  defp manage_score(%{winner: winner, attacker: attacker, defender: defender} = battle) do
    updates =
      if winner && winner.id == defender.id do
        turns = if attacker.pve_tier > 2, do: attacker.pve_current_turns + 1, else: attacker.pve_current_turns

        %{losses: attacker.losses + 1, pve_state: "dead", pve_current_turns: turns}
      else
        wins = if winner && winner.id == attacker.id, do: attacker.wins + 1, else: attacker.wins
        ties = if !winner, do: attacker.ties + 1, else: attacker.ties

        %{
          wins: wins,
          ties: ties
        }
      end

    {battle, updates}
  end

  defp manage_updates({%{attacker: attacker, rewards: %{total_gold: total_gold, total_xp: total_xp}} = battle, updates}) do
    {
      battle,
      Map.merge(updates, %{
        total_xp: total_xp,
        gold: attacker.gold + total_gold,
        total_gold_farm: attacker.total_gold_farm + total_gold
      })
    }
  end
end
