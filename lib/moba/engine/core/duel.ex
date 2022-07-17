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

  def valid?(%{attacker: %{id: attacker_id}, defender: %{id: defender_id}}) when attacker_id == defender_id, do: false
  def valid?(_), do: true

  def finalize_battle(battle) do
    battle
    |> manage_duel_winner()
    |> update_players()
    |> generate_snapshots()
    |> next_duel_phase()
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

  defp manage_duel_winner(%{winner_id: last_winner_id, duel: %{phase: phase} = duel} = last_battle)
       when phase == "opponent_battle" do
    first_battle = Engine.first_duel_battle(duel)

    player_win =
      last_winner_id && first_battle.winner_id == duel.player_first_pick_id &&
        last_winner_id == duel.player_second_pick_id

    opponent_win =
      last_winner_id && first_battle.winner_id == duel.opponent_first_pick_id &&
        last_winner_id == duel.opponent_second_pick_id

    diff = duel.opponent_player.pvp_points - duel.player.pvp_points
    multiplier = if duel.type == "pvp", do: 2, else: 1
    victory_points = Moba.victory_duel_points(diff) * multiplier
    defeat_points = Moba.defeat_duel_points(diff) * multiplier
    tie_points = Moba.tie_duel_points(diff) * multiplier

    {duel_winner, attacker_points, defender_points} =
      cond do
        player_win ->
          {duel.player, victory_points, victory_points * -1}

        opponent_win ->
          {duel.opponent_player, defeat_points * -1, defeat_points}

        true ->
          {nil, tie_points, tie_points * -1}
      end

    rewards = %{
      attacker_pvp_points: attacker_points,
      defender_pvp_points: defender_points
    }

    {duel_winner, Engine.update_battle!(last_battle, %{rewards: rewards})}
  end

  defp manage_duel_winner(battle), do: {nil, Engine.update_battle!(battle, %{rewards: %{}})}

  defp update_players(
         {duel_winner,
          %{rewards: rewards, duel: %{player: player, opponent_player: opponent, phase: phase, type: duel_type}} =
            battle}
       )
       when phase == "opponent_battle" do
    player_points = points_limits(player.pvp_points + rewards.attacker_pvp_points)
    opponent_points = points_limits(opponent.pvp_points + rewards.defender_pvp_points)

    player_updates =
      if duel_winner && player.id == duel_winner.id, do: %{duel_winner: player, loser_id: opponent.id}, else: %{}

    opponent_updates =
      if duel_winner && opponent.id == duel_winner.id, do: %{duel_winner: opponent, loser_id: player.id}, else: %{}

    Game.player_duel_updates!(player, duel_type, Map.merge(player_updates, %{pvp_points: player_points}))
    Game.player_duel_updates!(opponent, duel_type, Map.merge(opponent_updates, %{pvp_points: opponent_points}))

    {duel_winner, battle}
  end

  defp update_players({duel_winner, battle}), do: {duel_winner, battle}

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
    Game.next_duel_phase!(battle.duel)

    battle
  end

  defp points_limits(result) when result < 0, do: 0
  defp points_limits(result), do: result
end
