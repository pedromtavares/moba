defmodule Moba.Engine.Core do
  @moduledoc """
  Mid-level domain of all core battle mechanics.
  """

  alias Moba.{Engine, Repo}
  alias Engine.Core.{Duel, Helper, Match, League, Logger, Processor, Pve, Turns}
  alias Engine.Schema.Battle
  import Ecto.Query

  @doc """
  Automatically continues a battle until it finishes
  """
  def auto_finish_battle!({:error, _}, _), do: nil
  def auto_finish_battle!(nil, _), do: nil
  def auto_finish_battle!(%{training_team_id: id} = battle, _) when not is_nil(id), do: battle
  def auto_finish_battle!(%{finished: true} = battle, _), do: battle
  def auto_finish_battle!(battle, orders), do: battle |> continue_battle!(orders) |> auto_finish_battle!(orders)

  @doc """
  Creates a battle and jumps to a state where the attacker can start (case they are not the initiator)
  """
  def begin_battle!(battle, opts) do
    {:ok, result} =
      Repo.transaction(fn ->
        battle
        |> Turns.snapshot_loadouts()
        |> determine_initiator()
        |> Repo.insert!()
        |> maybe_skip_next_turn(opts)
        |> maybe_finalize_battle()
      end)

    result
  end

  defdelegate build_turn(battle, orders), to: Turns

  def can_use_resource?(%{attacker: attacker}, resource), do: Helper.can_use?(attacker, resource, :active)

  @doc "Preselects a forced continuation or the first castable skill in the hero's saved priority."
  def preselected_skill(%{attacker: %{double_skill: skill}}) when not is_nil(skill), do: skill

  def preselected_skill(%{attacker: attacker}) do
    Enum.find(attacker.skill_order, &(&1 && !&1.passive && Helper.can_use?(attacker, &1, :active)))
  end

  def create_duel_battle!(attrs), do: Duel.create_battle!(attrs)

  def create_league_battle!(attrs), do: League.create_battle!(attrs)

  def create_match_battle!(attrs), do: Match.create_battle!(attrs)

  def create_pve_battle!(target), do: Pve.create_battle!(target)

  @doc """
  Continues an existing battle by creating a new turn from where it left off
  """
  def continue_battle!(%{finished: true} = battle, _), do: battle
  def continue_battle!(%{training_team_id: id} = battle, _) when not is_nil(id), do: battle

  def continue_battle!(battle, orders) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.one!(from b in Battle, where: b.id == ^battle.id, lock: "FOR UPDATE")
        stored = Engine.get_battle!(battle.id)

        # Pre-upgrade battles acquire a fixed loadout on their next accepted turn.
        stored =
          if !stored.finished && stored.loadouts == %{} do
            Ecto.Changeset.change(stored, loadouts: Turns.snapshot_loadouts(stored).loadouts) |> Repo.update!()
          else
            stored
          end

        if !stored.finished && turn_number(stored) == turn_number(battle) && action_allowed?(stored, orders) do
          stored |> create_turn!(orders) |> maybe_finalize_battle()
        else
          stored
        end
      end)

    result
  end

  defp turn_number(battle) do
    case List.last(battle.turns) do
      nil -> 0
      turn -> turn.number
    end
  end

  defp action_allowed?(%{type: "match", match: %{interactive: true, player_id: owner}} = battle, %{player_id: id}) do
    id == owner && build_turn(battle, %{}).attacker.player_id == id
  end

  defp action_allowed?(%{type: "match"}, %{player_id: _}), do: false

  defp action_allowed?(battle, %{player_id: player_id, timeout: true}) do
    last = List.last(battle.turns)
    time = if last, do: last.inserted_at, else: battle.inserted_at

    player_id in [battle.attacker_player_id, battle.defender_player_id] &&
      NaiveDateTime.diff(NaiveDateTime.utc_now(), time) > Moba.turn_timer_in_seconds()
  end

  defp action_allowed?(battle, %{player_id: player_id}) do
    turn = build_turn(battle, %{})
    !is_nil(player_id) && turn.attacker.player_id == player_id
  end

  defp action_allowed?(_, _), do: true

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
  def determine_initiator(%{attacker: attacker, defender: defender} = battle) do
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

  # Interactive Arena turns are advanced individually after their animation finishes.
  defp maybe_skip_next_turn(%{match: %{interactive: true}} = battle, _) do
    Repo.preload(battle, turns: Engine.ordered_turns_query())
  end

  # Daily automatic matches and historical matches retain their original simulation.
  defp maybe_skip_next_turn(%{match_id: match_id} = battle, opts) when not is_nil(match_id) do
    battle = Repo.preload(battle, :turns)
    create_turn!(battle, Map.merge(opts, %{auto: true}))
  end

  # Skips to the next turn if the current action is to be performed by an automated opponent
  defp maybe_skip_next_turn(%{duel: %{auto: true, opponent_player_id: opponent_player_id}} = battle, _) do
    battle = Repo.preload(battle, turns: Engine.ordered_turns_query())
    last_turn = List.last(battle.turns)
    bot_initiator = is_nil(last_turn) && battle.initiator_player_id == opponent_player_id
    bot_attacker = last_turn && last_turn.defender.player_id == opponent_player_id
    attacker_disabled? = last_turn && Helper.disabled?(last_turn.defender)

    if bot_attacker || bot_initiator || attacker_disabled? do
      create_turn!(battle, %{auto: true})
    else
      battle
    end
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
