defmodule Moba.Engine.Core do
  @moduledoc """
  Mid-level domain of all core battle mechanics.
  """

  alias Moba.{Engine, Game, Repo}
  alias Engine.Core.{Duel, Helper, League, Logger, Processor, Pve, Turns}

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
  def begin_battle!(battle) do
    battle
    |> determine_initiator()
    |> Repo.insert!()
    |> maybe_skip_next_turn()
    |> maybe_finalize_battle()
  end

  defdelegate build_turn(battle, orders), to: Turns

  def can_use_resource?(%{attacker: attacker}, resource), do: Helper.can_use?(attacker, resource, :active)

  def create_pve_battle!(target), do: Pve.create_battle!(target)

  def create_league_battle!(attacker, defender), do: League.create_battle!(attacker, defender)

  def create_duel_battle!(attrs), do: Duel.create_battle!(attrs)

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

  def last_turn(battle) do
    battle = Repo.preload(battle, turns: Engine.ordered_turns_query())
    turn = List.last(battle.turns)

    turn &&
      %{
        turn
        | skill: turn.skill && Moba.struct_from_map(turn.skill, as: %Game.Schema.Skill{}),
          item: turn.item && Moba.struct_from_map(turn.item, as: %Game.Schema.Item{})
      }
  end

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
    |> maybe_skip_next_turn()
  end

  # Creates and processes a turn, finishing a battle if someone dies or it reaches the max turns count
  defp create_turn!(battle, orders) do
    build_turn(battle, orders)
    |> Processor.process_turn()
    |> Repo.insert!()
    |> battle_finished?()
  end

  # Uses the attacker's speed to calculate if they will initiate the battle. 1 speed = 1% chance
  defp determine_initiator(%{attacker: attacker, defender: defender} = battle) do
    roll = if attacker.pve_tier > 0, do: attacker.speed + attacker.item_speed, else: 100
    initiator = if roll >= Enum.random(1..100), do: attacker, else: defender

    %{battle | initiator: initiator}
  end

  defp determine_winner(%{battle: battle, attacker: attacker, defender: defender} = turn) do
    battle =
      cond do
        Helper.dead?(attacker) ->
          %{battle | winner: opponent(battle, attacker.hero_id)}

        Helper.dead?(defender) ->
          %{battle | winner: opponent(battle, defender.hero_id)}

        true ->
          %{battle | winner: battle.defender}
      end

    %{battle | turns: battle.turns ++ [turn]}
  end

  defp finalize_boss(%{type: "league", attacker: %{boss_id: boss_id} = hero, defender: boss, winner: winner} = battle)
       when winner == boss and not is_nil(boss_id) do
    last_turn = List.last(battle.turns)
    boss_battler = if last_turn.attacker.hero_id == boss_id, do: last_turn.attacker, else: last_turn.defender
    attacker = Game.finalize_boss!(boss, boss_battler.current_hp, hero)
    %{battle | attacker: attacker}
  end

  defp finalize_boss(battle), do: battle

  defp finish_battle(turn) do
    turn
    |> determine_winner()
    |> finalize_boss()
    |> Engine.update_battle!(%{finished: true})
  end

  defp maybe_finalize_battle(%{finished: true, type: "pve"} = battle), do: Pve.finalize_battle(battle)
  defp maybe_finalize_battle(%{finished: true, type: "league"} = battle), do: League.finalize_battle(battle)
  defp maybe_finalize_battle(%{finished: true, type: "duel"} = battle), do: Duel.finalize_battle(battle)
  defp maybe_finalize_battle(battle), do: battle

  # Skips to the next turn if the current action is to be performed by an automated opponent
  defp maybe_skip_next_turn(%{duel: %{auto: true}} = battle) do
    battle = Repo.preload(battle, :turns)
    create_turn!(battle, %{auto: true})
  end

  defp maybe_skip_next_turn(battle) do
    battle = Repo.preload(battle, turns: Engine.ordered_turns_query())
    last_turn = List.last(battle.turns)
    attacker_disabled? = last_turn && Helper.disabled?(last_turn.defender)

    if skip_bot_turn?(battle, last_turn) || attacker_disabled? do
      create_turn!(battle, %{auto: true})
    else
      battle
    end
  end

  defp skip_bot_turn?(
         %{
           type: "duel",
           attacker: attacker,
           defender: defender,
           initiator: initiator,
           duel: %{type: duel_type, player: %{id: player_id, bot_options: nil}}
         },
         last_turn
       )
       when duel_type != "pvp" do
    bot_initiator = is_nil(last_turn) && initiator.player_id != player_id
    bot_attacker = last_turn && last_turn.defender.hero_id == attacker.id && attacker.player_id != player_id
    bot_defender = last_turn && last_turn.defender.hero_id == defender.id && defender.player_id != player_id

    bot_initiator || bot_attacker || bot_defender
  end

  defp skip_bot_turn?(%{attacker: attacker, defender: defender, initiator: initiator}, last_turn) do
    bot_initiator = is_nil(last_turn) && initiator.bot_difficulty
    bot_attacker = last_turn && attacker.bot_difficulty && last_turn.defender.hero_id == attacker.id
    bot_defender = last_turn && defender.bot_difficulty && last_turn.defender.hero_id == defender.id

    bot_initiator || bot_attacker || bot_defender
  end
end
