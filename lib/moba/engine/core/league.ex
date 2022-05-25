defmodule Moba.Engine.Core.League do
  @moduledoc """
  Encapsulates all logic for League battles - the ones fought while in a League Challenge
  """

  alias Moba.{Game, Engine}
  alias Engine.Schema.Battle

  @master_league_tier Moba.master_league_tier()
  @turns_per_tier Moba.turns_per_tier()

  def create_battle!(%{league_step: step}, _) when step < 1 do
    {:error, "Not available"}
  end

  def create_battle!(attacker, defender) do
    battle_for(attacker, defender)
    |> Engine.begin_battle!()
    |> manage_first_step()
    |> update_attacker()
  end

  def finalize_battle(battle) do
    battle
    |> manage_step()
    |> finalize_attacker()
    |> maybe_generate_boss()
    |> maybe_finish_pve()
    |> Engine.generate_attacker_snapshot!()
  end

  defp battle_for(attacker, defender) do
    %Battle{
      attacker: attacker,
      defender: defender,
      type: Engine.battle_types().league
    }
  end

  defp manage_first_step(%{attacker: %{league_step: step, league_attempts: attempts}} = battle)
       when step == 1 do
    updates = %{league_attempts: attempts + 1}
    {battle, updates}
  end

  defp manage_first_step(battle), do: {battle, %{}}

  defp update_attacker({battle, updates}) when updates != %{} do
    Game.update_attacker!(battle.attacker, updates)

    battle
  end

  defp update_attacker({battle, _}), do: battle

  # Ranks the Hero up to the next league if they win on the last step, along with rewards. Sends to next step
  # on any other win and exits the challenge on a defeat.
  defp manage_step(
         %{
           winner: winner,
           attacker: %{league_step: step, league_successes: successes, league_tier: league_tier} = attacker
         } = battle
       ) do
    win = winner && attacker.id == winner.id

    {total_turns, current_turns} = league_turns(attacker)

    updates =
      cond do
        win && step >= Game.max_league_step_for(league_tier) ->
          next_league_tier = league_tier + 1

          %{
            league_step: 0,
            league_tier: next_league_tier,
            league_successes: successes + 1,
            gold: attacker.gold + league_bonus(attacker),
            total_xp: league_bonus(attacker),
            boss_id: nil,
            pve_current_turns: current_turns,
            pve_total_turns: total_turns,
            total_gold_farm: attacker.total_gold_farm + league_bonus(attacker)
          }

        win ->
          %{
            league_step: step + 1
          }

        league_tier == @master_league_tier ->
          %{
            league_step: 1
          }

        true ->
          %{
            league_step: 0,
            pve_current_turns: current_turns,
            pve_total_turns: total_turns,
            pve_state: "dead"
          }
      end

    {battle, updates}
  end

  # Automatically creates another League battle upon victory
  defp finalize_attacker({%{winner: winner} = battle, updates}) do
    attacker = Game.update_attacker!(battle.attacker, updates)

    if winner && attacker.id == winner.id && attacker.league_step > 0 do
      Engine.create_league_battle!(attacker)
    end

    {battle, attacker}
  end

  defp maybe_generate_boss({battle, attacker}) do
    attacker = Game.maybe_generate_boss(attacker)

    {battle, attacker}
  end

  defp maybe_finish_pve({battle, attacker}) do
    attacker = Game.maybe_finish_pve(attacker)

    {battle, attacker}
  end

  defp league_bonus(%{league_tier: @master_league_tier}), do: Moba.boss_win_bonus()
  defp league_bonus(_), do: Moba.league_win_bonus()

  defp league_turns(%{pve_total_turns: total_turns} = attacker) when total_turns >= @turns_per_tier do
    current_turns = attacker.pve_current_turns + @turns_per_tier
    total_turns = total_turns - @turns_per_tier
    {total_turns, current_turns}
  end

  defp league_turns(_), do: {0, 0}
end
