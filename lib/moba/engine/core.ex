defmodule Moba.Engine.Core do
  @moduledoc """
  Mid-level domain of all core battle mechanics.
  """

  alias Moba.{Engine, Repo, Game}
  alias Engine.Schema.{Turn, Battler}
  alias Engine.Core.{Processor, Pve, Pvp, League, Logger, Helper}

  @max_turns Moba.max_battle_turns()

  def create_pve_battle!(target), do: Pve.create_battle!(target)

  def create_pvp_battle!(attrs), do: Pvp.create_battle!(attrs)

  def create_league_battle!(attacker, defender), do: League.create_battle!(attacker, defender)

  @doc """
  Creates a battle and jumps to a state where the attacker can start (case they are not the initiator)
  """
  def start_battle!(battle) do
    battle
    |> determine_initiator()
    |> Repo.insert!()
    |> maybe_skip_next_turn()
    |> maybe_finalize_battle()
  end

  @doc """
  Continues an existing battle by creating a new turn from where it left off
  """
  def continue_battle!(%{finished: true} = battle, _), do: battle

  def continue_battle!(battle, orders) do
    battle
    |> create_turn!(orders)
    |> maybe_finalize_battle()
  end

  @doc """
  Automatically continues a battle until it finishes
  """
  def auto_finish_battle!({:error, _}, _), do: nil
  def auto_finish_battle!(nil, _), do: nil
  def auto_finish_battle!(%{finished: true} = battle, _), do: battle
  def auto_finish_battle!(battle, orders), do: battle |> continue_battle!(orders) |> auto_finish_battle!(orders)

  def build_turn(battle, orders) do
    last_turn = List.last(battle.turns)

    {attacker, defender} = build_battlers(battle, last_turn)

    %Turn{
      number: ((last_turn && last_turn.number) || 0) + 1,
      attacker: attacker,
      defender: defender,
      battle: battle,
      orders: orders
    }
  end

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

  def can_pvp?(attrs), do: Pvp.valid?(attrs)

  def effect_descriptions(turn), do: Logger.descriptions_for(turn)

  def can_use_resource?(%{attacker: attacker}, resource), do: Helper.can_use?(attacker, resource, :active)

  # Uses the attacker's speed to calculate if they will initiate the battle. 1 speed = 1% chance
  defp determine_initiator(%{attacker: attacker, defender: defender} = battle) do
    number =
      if attacker.level > 2 do
        buffed_total(attacker, battle, attacker.speed + attacker.item_speed)
      else
        100
      end

    initiator =
      if number >= Enum.random(0..100) do
        attacker
      else
        defender
      end

    %{battle | initiator: initiator}
  end

  defp maybe_finalize_battle(%{finished: true, type: "pve"} = battle), do: Pve.finalize_battle(battle)
  defp maybe_finalize_battle(%{finished: true, type: "pvp"} = battle), do: Pvp.finalize_battle(battle)
  defp maybe_finalize_battle(%{finished: true, type: "league"} = battle), do: League.finalize_battle(battle)
  defp maybe_finalize_battle(battle), do: battle

  # Creates and processes a turn, finishing a battle if someone dies or it reaches the max turns count
  defp create_turn!(battle, orders) do
    build_turn(battle, orders)
    |> Processor.process_turn()
    |> Repo.insert!()
    |> battle_finished?()
  end

  defp battle_finished?(%{attacker: %{current_hp: ahp}, defender: %{current_hp: dhp}} = turn)
       when ahp <= 0 or dhp <= 0 do
    finish_battle(turn)
  end

  defp battle_finished?(%{number: turn_number} = turn) when turn_number >= @max_turns do
    finish_battle(turn)
  end

  defp battle_finished?(turn) do
    battle = turn.battle

    %{battle | turns: battle.turns ++ [turn]}
    |> maybe_skip_next_turn()
  end

  defp finish_battle(turn) do
    turn
    |> determine_winner()
    |> Engine.update_battle!(%{finished: true})
  end

  # Skips to the next turn if the attacker can't do anything, such as the defender was the initiator
  # or the attacker was disabled
  defp maybe_skip_next_turn(battle) do
    battle = Repo.preload(battle, turns: Engine.ordered_turns_query())
    last_turn = List.last(battle.turns)

    cond do
      is_nil(last_turn) && battle.initiator == battle.defender -> create_turn!(battle, %{auto: true})
      last_turn && Helper.disabled?(last_turn.defender) -> create_turn!(battle, %{auto: true})
      last_turn && last_turn.defender.hero_id != battle.attacker_id -> create_turn!(battle, %{auto: true})
      true -> battle
    end
  end

  # Ties exist only in PVE
  defp determine_winner(%{battle: %{type: "pve"} = battle, attacker: attacker, defender: defender} = turn) do
    battle =
      cond do
        Helper.dead?(attacker) ->
          %{battle | winner: opponent(battle, attacker.hero_id)}

        Helper.dead?(defender) ->
          %{battle | winner: opponent(battle, defender.hero_id)}

        true ->
          %{battle | winner: nil}
      end

    %{battle | turns: battle.turns ++ [turn]}
  end

  # In both PVP and League battles, the attacker will lose if they do not manage to kill their opponent
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

  defp build_battlers(battle, last_turn) do
    if last_turn do
      {flush_attacker(last_turn.defender), flush_defender(last_turn.attacker)}
    else
      {build_battler(battle.initiator, battle), build_battler(opponent(battle, battle.initiator_id), battle)}
    end
  end

  # Heroes do not exist in the Engine domain, they must be transformed to a Battler
  defp build_battler(hero, battle) do
    hero = Repo.preload(hero, [:items, :avatar, active_build: [:skills]])
    skills = hero.active_build.skills
    items = hero.items

    %Battler{
      hero_id: hero.id,
      name: hero.name,
      code: hero.avatar.code,
      image: hero.avatar.image,
      is_bot: !is_nil(hero.bot_difficulty),
      level: hero.level,
      total_hp: buffed_total(hero, battle, hero.total_hp + hero.item_hp),
      total_mp: buffed_total(hero, battle, hero.total_mp + hero.item_mp),
      current_hp: buffed_total(hero, battle, hero.total_hp + hero.item_hp),
      current_mp: buffed_total(hero, battle, hero.total_mp + hero.item_mp),
      last_hp: buffed_total(hero, battle, hero.total_hp + hero.item_hp),
      speed: buffed_total(hero, battle, hero.speed + hero.item_speed),
      atk: buffed_total(hero, battle, hero.atk + hero.item_atk),
      power: buffed_total(hero, battle, hero.power + hero.item_power),
      armor: buffed_total(hero, battle, hero.armor + hero.item_armor),
      base_atk: buffed_total(hero, battle, hero.atk + hero.item_atk),
      base_power: buffed_total(hero, battle, hero.power + hero.item_power),
      base_armor: buffed_total(hero, battle, hero.armor + hero.item_armor),
      active_skills: skills |> Enum.filter(&(!&1.passive)),
      passive_skills: skills |> Enum.filter(& &1.passive),
      active_items: items |> Enum.filter(& &1.active),
      passive_items: items |> Enum.filter(&(!&1.active)),
      skill_order: codes_to_resources(hero.active_build.skill_order, [Moba.basic_attack() | skills]),
      item_order: codes_to_resources(hero.active_build.item_order, items)
    }
  end

  defp opponent(battle, hero_id) do
    if battle.attacker_id == hero_id do
      battle.defender
    else
      battle.attacker
    end
  end

  defp codes_to_resources(codes, pool) do
    Enum.map(codes, fn code ->
      Enum.find(pool, fn resource -> resource.code == code end)
    end)
  end

  # Heroes receive a buff (stat increase) when they rank up to a new league -- only applied in PVE
  defp buffed_total(%{buffed_battles_available: battles}, %{type: type}, total) when type == "pve" and battles > 0,
    do: total + round(Moba.league_buff_multiplier() * total)

  defp buffed_total(_, _, total), do: total

  # flushes necessary stats for an attacker on a new turn (was a defender last turn)
  defp flush_attacker(attacker) do
    %{
      attacker
      | invulnerable: false,
        physically_invulnerable: false,
        inneffectable: false,
        turn_armor: attacker.turn_armor + attacker.next_armor,
        turn_power: attacker.turn_power + attacker.next_power,
        turn_power_normal: attacker.turn_power_normal + attacker.next_power_normal,
        turn_power_magic: attacker.turn_power_magic + attacker.next_power_magic,
        next_armor: 0,
        next_power: 0,
        next_power_normal: 0,
        next_power_magic: 0,
        double_skill: load_skill(attacker.double_skill),
        delayed_skill: load_skill(attacker.delayed_skill)
    }
    |> flush()
  end

  # flushes necessary stats for a defender on a new turn (was an attacker last turn)
  defp flush_defender(defender) do
    %{
      defender
      | turn_armor: 0,
        turn_power: 0,
        turn_power_normal: 0,
        turn_power_magic: 0,
        turn_atk: 0,
        purged_power: 0,
        miss: false,
        silenced: false,
        stunned: false,
        disarmed: false
    }
    |> flush()
  end

  defp flush(battler) do
    %{
      battler
      | damage: 0,
        hp_regen: 0,
        mp_regen: 0,
        mp_burn: 0,
        total_buff: 0,
        total_reduction: 0,
        null_armor: false,
        effects: [],
        active_skills: load_skills(battler.active_skills),
        passive_skills: load_skills(battler.passive_skills),
        active_items: load_items(battler.active_items),
        passive_items: load_items(battler.passive_items),
        skill_order: load_skills(battler.skill_order),
        item_order: load_items(battler.item_order),
        last_skill: load_skill(battler.last_skill),
        buffs: load_buffs(battler.buffs),
        debuffs: load_buffs(battler.debuffs),
        defender_buffs: load_buffs(battler.defender_buffs)
    }
  end

  defp load_buffs(buffs) do
    Enum.map(buffs, fn buff ->
      resource = buff[:resource] || buff["resource"]
      duration = buff[:duration] || buff["duration"]
      %{resource: load_skill(resource), duration: duration}
    end)
  end

  defp load_skill(map), do: load_resource(map, %Game.Schema.Skill{})

  defp load_skills(list), do: Enum.map(list, &load_skill(&1))

  defp load_items(list) do
    Enum.map(list, fn map -> load_resource(map, %Game.Schema.Item{}) end)
  end

  defp load_resource(nil, _), do: nil
  defp load_resource(map, struct), do: Moba.struct_from_map(map, as: struct)
end
