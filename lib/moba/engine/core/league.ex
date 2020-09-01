defmodule Moba.Engine.Core.League do
  @moduledoc """
  Encapsulates all logic for League battles - the ones fought while in a League Challenge
  """

  alias Moba.{Game, Engine}
  alias Engine.Schema.Battle

  def create_battle!(%{league_step: step}, _) when step < 1 do
    {:error, "Not available"}
  end

  def create_battle!(attacker, defender) do
    battle_for(attacker, defender)
    |> Engine.start_battle!()
    |> manage_first_step()
    |> update_attacker()
  end

  def finalize_battle(battle) do
    battle
    |> manage_step()
    |> finalize_attacker()
    |> Engine.generate_attacker_snapshot!()
  end

  defp battle_for(attacker, defender) do
    %Battle{
      attacker: attacker,
      defender: defender,
      match_id: attacker.match_id,
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

    updates =
      cond do
        win && step >= Game.max_league_step_for(league_tier) ->
          %{
            league_step: 0,
            league_tier: league_tier + 1,
            league_successes: successes + 1,
            gold: attacker.gold + Moba.league_win_gold_bonus(),
            buffed_battles_available: Moba.league_win_buffed_battles_bonus()
          }

        win ->
          %{
            league_step: step + 1
          }

        true ->
          %{
            league_step: 0
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
end
