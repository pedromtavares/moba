defmodule Moba.Engine.Core.Pvp do
  @moduledoc """
  Encapsulates all logic for PVP battles - the ones fought in the Arena
  """

  alias Moba.{Game, Engine}
  alias Engine.Schema.Battle

  use Timex

  def create_battle!(attrs) do
    if valid?(attrs) do
      battle_for(attrs)
      |> Engine.start_battle!()
      |> manage_history()
      |> update_attacker()
    else
      {:error, "Invalid target"}
    end
  end

  @doc """
  Exclusive to PVP, heroes cannot attack the same target more than once, and this checks
  that the defender is not a recent target in the attacker's pvp_history
  """
  def valid?(%{attacker: %{id: attacker_id}, defender: %{id: defender_id}}) when attacker_id == defender_id, do: false

  def valid?(%{attacker: %{pvp_history: history}, defender: %{id: defender_id}}) do
    time = Map.get(history, Integer.to_string(defender_id))

    if is_nil(time) do
      true
    else
      parsed = Timex.parse!(time, "{ISO:Extended:Z}")
      Timex.before?(parsed, Timex.now())
    end
  end

  def finalize_battle(battle) do
    battle
    |> manage_rewards()
    |> manage_unread()
    |> manage_score()
    |> update_heroes()
    |> generate_snapshots()
    |> update_ranking()
  end

  defp battle_for(%{attacker: attacker, defender: defender}) do
    %Battle{
      attacker: attacker,
      defender: defender,
      match_id: Game.current_match().id,
      type: Engine.battle_types().pvp
    }
  end

  # Saves the defender in the attacker's pvp_history
  defp manage_history(%{attacker: %{pvp_history: history}, defender: defender} = battle) do
    timeout = Timex.shift(Timex.now(), hours: Moba.pvp_timeout_in_hours())
    history = Map.put(history, Integer.to_string(defender.id), timeout)
    {battle, %{pvp_history: history}}
  end

  defp update_attacker({%{attacker: attacker} = battle, updates}) do
    Game.update_attacker!(attacker, updates)

    battle
  end

  # PVP points are calculated based on the difference of points between heroes, the lower the difference, the
  # more the attacker has to lose and vice-versa. Defenders also gain and lose points.
  defp manage_rewards(%{winner: winner, attacker: attacker, defender: defender} = battle) do
    win = attacker.id == winner.id

    diff = defender.pvp_points - attacker.pvp_points

    {attacker_points, defender_points} =
      cond do
        win -> {Moba.attacker_win_pvp_points(diff), Moba.defender_loss_pvp_points(diff)}
        true -> {Moba.attacker_loss_pvp_points(diff), Moba.defender_win_pvp_points(diff)}
      end

    rewards = %{
      attacker_pvp_points: attacker_points,
      defender_pvp_points: defender_points
    }

    Engine.update_battle!(battle, %{rewards: rewards})
  end

  # Alerts the defender that the battle happened
  defp manage_unread(%{defender: defender} = battle) do
    Engine.broadcast_unread(defender)

    Engine.update_battle!(battle, %{unread_id: defender.id})
  end

  # This passes score information along to be updated in the User's pvp_score
  defp manage_score(%{winner: winner, attacker: attacker, defender: defender} = battle) do
    win = winner && attacker.id == winner.id

    {attacker_updates, defender_updates} =
      if win do
        {
          %{pvp_wins: attacker.pvp_wins + 1, loser_user_id: defender.user_id},
          %{pvp_losses: defender.pvp_losses + 1}
        }
      else
        {
          %{pvp_losses: attacker.pvp_losses + 1},
          %{pvp_wins: defender.pvp_wins + 1, loser_user_id: attacker.user_id}
        }
      end

    {battle, attacker_updates, defender_updates}
  end

  # Updates heroes with the points they were given, respecting the minimum amount which is 0
  defp update_heroes(
         {%{attacker: attacker, defender: defender, rewards: rewards} = battle, attacker_updates, defender_updates}
       ) do
    attacker_updates =
      attacker_updates
      |> Map.merge(%{
        pvp_points: points_limits(attacker.pvp_points + rewards.attacker_pvp_points, attacker)
      })

    defender_updates =
      defender_updates
      |> Map.merge(%{
        pvp_points: points_limits(defender.pvp_points + rewards.defender_pvp_points, defender)
      })

    attacker = Game.update_attacker!(attacker, attacker_updates)
    defender = Game.update_defender!(defender, defender_updates)

    {battle, attacker, defender}
  end

  defp generate_snapshots({battle, attacker, defender}) do
    battle = Engine.generate_attacker_snapshot!({battle, attacker, defender})
    Engine.generate_defender_snapshot!({battle, attacker, defender})
  end

  defp update_ranking(battle) do
    Moba.run_async(fn -> Game.update_ranking!() end)

    battle
  end

  defp points_limits(result, _) when result < 0, do: 0

  defp points_limits(result, _), do: result
end
