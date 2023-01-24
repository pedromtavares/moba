defmodule Moba.Engine.Core do
  @moduledoc """
  Mid-level domain of all core battle mechanics.
  """

  alias Moba.{Engine, Repo}
  alias Engine.Core.{Duel, Helper, Match, League, Logger, Processor, Pve, Turns}

  @doc """
  Automatically continues a battle until it finishes
  """
  def auto_finish_battle!({:error, _}, _), do: nil
  def auto_finish_battle!(nil, _), do: nil
  def auto_finish_battle!(%{finished: true} = battle, _), do: battle
  def auto_finish_battle!(battle, orders), do: battle |> continue_battle!(orders) |> auto_finish_battle!(orders)

  @doc """
  Creates a battle and jumps to a state where the attacker can start (case they are not the initiator)
  """
  def begin_battle!(battle, opts) do
    battle
    |> determine_initiator()
    |> Repo.insert!()
    |> maybe_skip_next_turn(opts)
    |> maybe_finalize_battle()
  end

  defdelegate build_turn(battle, orders), to: Turns

  def can_use_resource?(%{attacker: attacker}, resource), do: Helper.can_use?(attacker, resource, :active)

  def create_duel_battle!(attrs), do: Duel.create_battle!(attrs)

  def create_league_battle!(attrs), do: League.create_battle!(attrs)

  def create_match_battle!(attrs), do: Match.create_battle!(attrs)

  def create_pve_battle!(target), do: Pve.create_battle!(target)

  @doc """
  Continues an existing battle by creating a new turn from where it left off
  """
  def continue_battle!(%{finished: true} = battle, _), do: battle

  def continue_battle!(battle, orders) do
    battle
    |> create_turn!(orders)
    |> maybe_finalize_battle()
  end

  def effect_descriptions(turn), do: Logger.descriptions_for(turn)

  def opponent(%{attacker_id: attacker_id} = battle, hero_id) when attacker_id == hero_id, do: battle.defender
  def opponent(battle, _), do: battle.attacker

  # ---------------------------------------------

  defp battle_finished?(%{attacker: %{current_hp: ahp}, defender: %{current_hp: dhp}} = turn)
       when ahp <= 0 or dhp <= 0 do
    finish_battle(turn)
  end

  defp battle_finished?(%{number: turn_number} = turn) when turn_number >= 100 do
    finish_battle(turn)
  end

  defp battle_finished?(%{battle: battle} = turn) do
    %{battle | turns: battle.turns ++ [turn]}
    |> maybe_skip_next_turn(%{})
  end

  # Creates and processes a turn, finishing a battle if someone dies or it reaches the max turns count
  defp create_turn!(battle, orders) do
    build_turn(battle, orders)
    |> Processor.process_turn()
    |> Turns.serialize()
    |> Repo.insert!()
    |> battle_finished?()
  end

  # Uses the attacker's speed to calculate if they will initiate the battle. 1 speed = 1% chance
  defp determine_initiator(%{attacker: attacker, defender: defender} = battle) do
    roll = if attacker.pve_tier > 0, do: attacker.speed + attacker.item_speed, else: 100

    {initiator, initiator_player} =
      if roll >= Enum.random(1..100) do
        {attacker, battle.attacker_player}
      else
        {defender, battle.defender_player}
      end

    %{battle | initiator: initiator, initiator_player: initiator_player}
  end

  defp determine_winner(%{battle: battle, attacker: attacker, defender: defender} = turn) do
    battle =
      cond do
        Helper.dead?(attacker) ->
          %{battle | winner: opponent(battle, attacker.hero_id), winner_player: player_for(defender.player_id, battle)}

        Helper.dead?(defender) ->
          %{battle | winner: opponent(battle, defender.hero_id), winner_player: player_for(attacker.player_id, battle)}

        true ->
          %{battle | winner: battle.defender, winner_player: battle.defender_player}
      end

    %{battle | turns: battle.turns ++ [turn]}
  end

  defp finish_battle(turn) do
    turn
    |> determine_winner()
    |> Engine.update_battle!(%{finished: true})
  end

  defp maybe_finalize_battle(%{finished: true, type: "pve"} = battle), do: Pve.finalize_battle(battle)
  defp maybe_finalize_battle(%{finished: true, type: "league"} = battle), do: League.finalize_battle(battle)
  defp maybe_finalize_battle(%{finished: true, type: "duel"} = battle), do: Duel.finalize_battle(battle)
  defp maybe_finalize_battle(battle), do: battle

  # All match battles are automated
  defp maybe_skip_next_turn(%{match_id: match_id} = battle, opts) when not is_nil(match_id) do
    battle = Repo.preload(battle, :turns)
    create_turn!(battle, Map.merge(opts, %{auto: true}))
  end

  # Skips to the next turn if the current action is to be performed by an automated opponent
  defp maybe_skip_next_turn(%{duel: %{auto: true}} = battle, _) do
    battle = Repo.preload(battle, :turns)
    create_turn!(battle, %{auto: true})
  end

  defp maybe_skip_next_turn(battle, _) do
    battle = Repo.preload(battle, turns: Engine.ordered_turns_query())
    last_turn = List.last(battle.turns)
    attacker_disabled? = last_turn && Helper.disabled?(last_turn.defender)

    if skip_bot_turn?(battle, last_turn) || attacker_disabled? do
      create_turn!(battle, %{auto: true})
    else
      battle
    end
  end

  defp player_for(player_id, %{attacker_player_id: apid} = battle) when player_id == apid, do: battle.attacker_player
  defp player_for(_, battle), do: battle.defender_player

  defp skip_bot_turn?(%{type: "duel"}, _), do: false

  defp skip_bot_turn?(%{attacker: attacker, defender: defender, initiator: initiator}, last_turn) do
    bot_initiator = is_nil(last_turn) && initiator.bot_difficulty
    bot_attacker = last_turn && attacker.bot_difficulty && last_turn.defender.hero_id == attacker.id
    bot_defender = last_turn && defender.bot_difficulty && last_turn.defender.hero_id == defender.id

    bot_initiator || bot_attacker || bot_defender
  end
end
