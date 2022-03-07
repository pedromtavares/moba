defmodule Moba.Engine.Core.Duel do
  @moduledoc """
  Encapsulates all logic for Duel battles
  """

  alias Moba.{Accounts, Game, Engine}
  alias Engine.Schema.Battle

  def create_battle!(attrs) do
    if valid?(attrs) do
      battle_for(attrs)
      |> Engine.start_battle!()
    else
      {:error, "Invalid target"}
    end
  end

  def valid?(%{attacker: %{id: attacker_id}, defender: %{id: defender_id}}) when attacker_id == defender_id, do: false
  def valid?(_), do: true

  def finalize_battle(battle) do
    battle
    |> manage_duel_winner()
    |> update_users()
    |> generate_snapshots()
    |> next_duel_phase()
  end

  defp battle_for(%{attacker: attacker, defender: defender, duel_id: duel_id}) do
    %Battle{
      attacker: attacker,
      defender: defender,
      match_id: Moba.current_match().id,
      duel_id: duel_id,
      type: Engine.battle_types().duel
    }
  end

  defp manage_duel_winner(%{winner: winner, duel: %{phase: phase} = duel} = last_battle)
       when phase == "opponent_battle" do
    first_battle = Engine.first_duel_battle(duel)
    user_win = first_battle.winner_id == duel.user_first_pick_id && winner.id == duel.user_second_pick_id
    opponent_win = first_battle.winner_id == duel.opponent_first_pick_id && winner.id == duel.opponent_second_pick_id

    diff = duel.opponent.season_points - duel.user.season_points

    multiplier = if duel.type == "pvp", do: 2, else: 0.5

    {duel_winner, attacker_points, defender_points} =
      cond do
        user_win ->
          {duel.user, round(Moba.attacker_win_pvp_points(diff) * multiplier), round(Moba.defender_loss_pvp_points(diff) * multiplier)}

        opponent_win ->
          {duel.opponent, round(Moba.attacker_loss_pvp_points(diff) * multiplier), round(Moba.defender_win_pvp_points(diff) * multiplier)}

        true ->
          {nil, 0, 0}
      end

    rewards = %{
      attacker_pvp_points: attacker_points,
      defender_pvp_points: defender_points
    }

    {duel_winner, Engine.update_battle!(last_battle, %{rewards: rewards})}
  end

  defp manage_duel_winner(battle), do: {nil, Engine.update_battle!(battle, %{rewards: %{}})}

  defp update_users({duel_winner, %{rewards: rewards, duel: %{user: user, opponent: opponent, phase: phase}} = battle})
       when phase == "opponent_battle" do
    user_points = points_limits(user.season_points + rewards.attacker_pvp_points)
    opponent_points = points_limits(opponent.season_points + rewards.defender_pvp_points)

    user_updates =
      if duel_winner && user.id == duel_winner.id, do: %{duel_winner: user, loser_id: opponent.id}, else: %{}

    opponent_updates =
      if duel_winner && opponent.id == duel_winner.id, do: %{duel_winner: opponent, loser_id: user.id}, else: %{}

    Accounts.user_duel_updates!(user, Map.merge(user_updates, %{season_points: user_points}))
    Accounts.user_duel_updates!(opponent, Map.merge(opponent_updates, %{season_points: opponent_points}))

    {duel_winner, battle}
  end

  defp update_users({duel_winner, battle}), do: {duel_winner, battle}

  defp generate_snapshots({duel_winner, battle}) do
    battle = Engine.generate_attacker_snapshot!({battle, battle.attacker, battle.defender})
    battle = Engine.generate_defender_snapshot!({battle, battle.attacker, battle.defender})
    {duel_winner, battle}
  end

  defp next_duel_phase({duel_winner, %{duel: %{phase: phase} = duel} = battle}) when phase == "opponent_battle" do
    Game.finish_duel!(duel, duel_winner, Map.from_struct(battle.rewards))

    battle
  end

  defp next_duel_phase({_, battle}) do
    Game.get_duel!(battle.duel_id) |> Game.next_duel_phase!()

    battle
  end

  defp points_limits(result) when result < 0, do: 0
  defp points_limits(result), do: result
end
