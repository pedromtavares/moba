defmodule Moba.Engine.Core.Pve do
  @moduledoc """
  Encapsulates all logic for PVE battles - the ones fought in the Jungle
  """
  alias Moba.{Game, Engine}
  alias Engine.Schema.Battle

  @pve_points_limit Moba.pve_points_limit()

  def create_battle!(%{attacker: %{pve_battles_available: battles}}) when battles < 1 do
    {:error, "Not enough available battles"}
  end

  def create_battle!(target) do
    target
    |> battle_for()
    |> Engine.start_battle!()
    |> manage_available_battles()
    |> update_attacker()
    |> generate_targets()
  end

  def finalize_battle(battle) do
    battle
    |> manage_rewards()
    |> manage_streaks()
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

  defp manage_available_battles(%{attacker: attacker} = battle) do
    updates = %{pve_battles_available: attacker.pve_battles_available - 1}
    {battle, updates}
  end

  defp update_attacker({battle, updates}) do
    attacker = Moba.update_attacker!(battle.attacker, updates)

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

  # Calculates XP, gold and points given, all depending on battle difficulty and outcome (victory/tie/loss)
  defp manage_rewards(%{winner: winner, difficulty: difficulty, attacker: attacker} = battle) do
    base_xp = battle_xp(attacker)
    percentage = Moba.xp_percentage(difficulty)
    streak_percentage = Moba.streak_percentage(difficulty)

    win = winner && attacker.id == winner.id
    alive = win || is_nil(winner)

    battle_xp = (alive && base_xp |> final_xp_value(percentage)) || 0
    loss_streak_xp = (alive && loss_streak_xp(attacker) |> final_xp_value(streak_percentage)) || 0

    win_xp = (win && base_xp |> final_xp_value(percentage)) || 0
    win_streak_xp = (alive && win_streak_xp(attacker) |> final_xp_value(streak_percentage)) || 0

    pve_points = !Game.max_league?(attacker) && difficulty_pve_points(difficulty, win, alive)

    total = battle_xp + win_xp + win_streak_xp + loss_streak_xp

    rewards = %{
      battle_xp: battle_xp,
      win_xp: win_xp,
      win_streak_xp: win_streak_xp,
      loss_streak_xp: loss_streak_xp,
      difficulty_percentage: percentage,
      total_xp: total,
      total_gold: total,
      total_pve_points: pve_points || 0
    }

    Engine.update_battle!(battle, %{rewards: rewards})
  end

  defp final_xp_value(total, percentage) do
    (total * percentage / 100)
    |> Float.round()
    |> trunc()
  end

  # Streaks are an exclusive to PVE battles and are used to give bonus rewards.
  defp manage_streaks(%{winner: winner, attacker: attacker, defender: defender} = battle) do
    updates =
      if winner && winner.id == defender.id do
        %{loss_streak: attacker.loss_streak + 1, win_streak: 0, losses: attacker.losses + 1}
      else
        new_streak = attacker.win_streak + 1
        best_streak = if new_streak > attacker.best_pve_streak, do: new_streak, else: attacker.best_pve_streak
        wins = if winner && winner.id == attacker.id, do: attacker.wins + 1, else: attacker.wins
        ties = if !winner, do: attacker.ties + 1, else: attacker.ties

        %{
          win_streak: new_streak,
          loss_streak: 0,
          wins: wins,
          ties: ties,
          best_pve_streak: best_streak
        }
      end

    {battle, updates}
  end

  defp manage_updates({%{attacker: attacker, rewards: rewards} = battle, updates}) do
    {
      battle,
      Map.merge(updates, %{
        total_xp: rewards.total_xp,
        gold: attacker.gold + rewards.total_gold,
        total_farm: attacker.total_farm + rewards.total_gold,
        buffed_battles_available: zero_limit(attacker.buffed_battles_available - 1),
        xp_boosted_battles_available: attacker.xp_boosted_battles_available - 1,
        pve_points: points_limit(attacker.pve_points + rewards.total_pve_points)
      })
    }
  end

  defp battle_xp(%{xp_boosted_battles_available: xp_boost}) when xp_boost > 0, do: Moba.battle_xp() * 2
  defp battle_xp(_), do: Moba.battle_xp()

  defp difficulty_pve_points(difficulty, win, _) when win == true do
    Moba.victory_pve_points(difficulty)
  end

  defp difficulty_pve_points(difficulty, _, alive) when alive == true do
    Moba.tie_pve_points(difficulty)
  end

  defp difficulty_pve_points(_, _, _), do: 0

  defp loss_streak_xp(hero), do: Moba.loss_streak_xp(hero.loss_streak)

  # we give the XP for an extra win since XP is given before the streak manager actually adds a win
  defp win_streak_xp(hero), do: Moba.win_streak_xp(hero.win_streak + 1)

  defp points_limit(result) when result > @pve_points_limit, do: @pve_points_limit
  defp points_limit(result), do: result

  defp zero_limit(number) when number < 0, do: 0
  defp zero_limit(number), do: number
end
