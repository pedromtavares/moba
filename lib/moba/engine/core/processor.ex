defmodule Moba.Engine.Core.Processor do
  @moduledoc """
  Orchestrates the core mechanics, processing a Turn from start to finish.
  """

  alias Moba.Engine.Core
  alias Core.{Effect, Helper, Spell}
  require Logger

  @doc """
  Processes a turn in the specified order of events. Each function needs to return
  a modified Turn object to be used by the next function.
  """
  def process_turn(turn) do
    turn
    |> apply_buffs()
    |> apply_debuffs()
    |> apply_permanent_skill()
    |> calculate_atk()
    |> attack()
    |> tick_cooldowns()
    |> passives()
    |> increases_and_reductions()
    |> apply_defender_buffs()
    |> defend()
    |> final_effects()
    |> finish()
  end

  @doc """
  Applies all base effects of casting a Skill. This is a public function due to special Spells
  like spell_steal and rearm which need to call this directly.
  """
  def cast_skill(turn, %{code: "basic_attack"}), do: basic_attack(turn)

  def cast_skill(turn, skill) do
    Logger.info("Skill cast: #{skill.code}")

    %{turn | resource: skill, skill: skill}
    |> Effect.damage_type(Moba.damage_types().magic)
    |> apply_spell()
    |> Effect.mp_cost()
    |> Effect.add_cooldown()
    |> Effect.add_last_skill()
    |> Effect.increment_spell_count()
  end

  # Buffs are benevolent effects that the attacker casts on itself.
  # They are applied every turn until their duration wears off.
  defp apply_buffs(%{attacker: %{buffs: buffs}} = turn) do
    Enum.reduce(buffs, turn, fn %{resource: buff, duration: duration}, acc ->
      acc |> apply_buff(buff, duration)
    end)
  end

  # Debuffs are malevolent effects that the attacker casts on the defender.
  # They are applied every turn until their duration wears off.
  defp apply_debuffs(%{defender: %{debuffs: debuffs}} = turn) do
    Enum.reduce(debuffs, turn, fn %{resource: debuff, duration: duration}, acc ->
      acc |> apply_debuff(debuff, duration)
    end)
  end

  # permanent_skills apply every attacking turn until they are canceled.
  defp apply_permanent_skill(%{attacker: %{permanent_skill: skill}} = turn) when not is_nil(skill) do
    %{turn | resource: skill} |> apply_spell()
  end

  defp apply_permanent_skill(turn), do: turn

  # atk stat needs to be calculated before the attack phase starts
  defp calculate_atk(turn) do
    %{turn | attacker: Helper.calculate_atk(turn.attacker)}
  end

  # delayed_skills get applied on the turn after they are cast
  # Here, it is prioritized as the first action taken on the attack phase
  defp attack(%{attacker: %{delayed_skill: skill}} = turn) when not is_nil(skill) do
    turn = %{turn | resource: skill} |> apply_spell()

    turn
    |> Map.put(:attacker, %{turn.attacker | delayed_skill: nil})
    |> attack()
  end

  # Stunned attackers cannot attack and get their current double_skill canceled
  defp attack(%{attacker: %{stunned: true} = attacker} = turn) do
    attacker = %{attacker | stun_count: attacker.stun_count + 1}

    %{turn | attacker: attacker, resource: %{code: "stunned"}}
    |> Effect.remove_double_skill()
  end

  # Silenced attackers must attack with a basic_attack and also get their current
  # double_skill canceled
  defp attack(%{attacker: %{silenced: true}} = turn) do
    turn
    |> basic_attack()
    |> Effect.remove_double_skill()
  end

  # Default attack case, using the skill and item chosen on the UI
  defp attack(turn) do
    turn
    |> use_skill()
    |> use_item()
  end

  # Decrements all future cooldowns from the attacker by 1 and sets them as current cooldowns for future turns
  defp tick_cooldowns(%{attacker: %{future_cooldowns: cooldowns} = attacker} = turn) when map_size(cooldowns) > 0 do
    result =
      Enum.reduce(cooldowns, %{}, fn {key, val}, acc ->
        Map.put(acc, key, val - 1)
      end)

    %{turn | attacker: %{attacker | cooldowns: result, future_cooldowns: result}}
  end

  defp tick_cooldowns(turn), do: turn

  # Applies passive spells, which cannot be activated and generally do not cost MP
  # Not triggered if the attacker is stunned
  defp passives(%{attacker: %{stunned: true}} = turn), do: turn

  defp passives(%{attacker: attacker, defender: defender} = turn) do
    turn
    |> use_passives(%{owner: attacker, is_attacking: true})
    |> use_passives(%{owner: defender, is_attacking: false})
  end

  # Applies increases and reductions to both attacker (in case of self damage) and
  # defender (in case of damage)
  # Note that increases (provided by Power) are also applied to HP and MP regen
  defp increases_and_reductions(%{attacker: attacker, defender: defender} = turn) do
    total_buff = Helper.calculate_damage_buff(attacker, defender)
    attacker_self_damage = attacker.self_damage * total_buff
    attacker_damage = if attacker.damage < 0, do: 0, else: attacker.damage
    defender_damage = defender.damage + defender.damage * total_buff
    attacker_hp_regen = attacker.hp_regen + attacker.hp_regen * total_buff
    attacker_mp_regen = attacker.mp_regen + attacker.mp_regen * total_buff

    attacker = %{
      attacker
      | damage: round(attacker_damage + attacker_self_damage),
        last_damage_caused: round(defender_damage),
        hp_regen: round(attacker_hp_regen),
        mp_regen: round(attacker_mp_regen),
        total_buff: total_buff
    }

    total_reduction = Helper.calculate_damage_reduction(defender)
    defender_damage = defender_damage - defender_damage * total_reduction
    defender_damage = if defender_damage < 0, do: 0, else: round(defender_damage)

    defender = %{
      defender
      | damage: defender_damage,
        last_damage_taken: defender_damage,
        total_reduction: total_reduction
    }

    %{turn | attacker: attacker, defender: defender}
  end

  # Defender Buffs are benevolent effects that the attacker casts on itself to be applied on the next turn.
  # They are applied every turn until their duration wears off.
  defp apply_defender_buffs(%{defender: %{defender_buffs: buffs}} = turn) do
    Enum.reduce(buffs, turn, fn %{resource: buff, duration: duration}, acc ->
      acc |> apply_defender_buff(buff, duration)
    end)
  end

  defp defend(turn) do
    turn
    |> defend_effects()
    |> defend_damage()
  end

  defp defend_damage(%{attacker: %{disarmed: true}, defender: %{damage_type: type} = defender} = turn)
       when type == "normal" do
    %{turn | defender: %{defender | damage: 0}}
    |> Effect.disarmed()
  end

  defp defend_damage(%{defender: %{damage_type: type, physically_invulnerable: true} = defender} = turn)
       when type == "normal" do
    %{turn | defender: %{defender | damage: 0}}
    |> Effect.invulnerable()
  end

  defp defend_damage(%{defender: %{invulnerable: true, damage_type: type} = defender} = turn)
       when type != "pure" do
    %{turn | defender: %{defender | damage: 0}}
    |> Effect.invulnerable()
  end

  defp defend_damage(turn), do: turn

  defp defend_effects(%{defender: %{inneffectable: true} = defender} = turn) do
    %{turn | defender: %{defender | mp_burn: 0, stunned: false, silenced: false}}
  end

  defp defend_effects(turn), do: turn

  # Applies a list of final_effects that ignore all increases, reductions and defenses
  defp final_effects(%{final_effects: effects} = turn) when length(effects) > 0 do
    Enum.reduce(effects, turn, fn resource, acc ->
      acc |> apply_final_resource(resource)
    end)
  end

  defp final_effects(turn), do: turn

  # Calculates stats after all effects are applied and properly increased/reduced
  # This is the final step of the turn processing
  defp finish(%{attacker: turn_attacker, defender: turn_defender} = turn) do
    finalized_attacker = finalize_attacker(turn_attacker, turn_defender)
    finalized_defender = finalize_defender(turn_defender)

    %{turn | attacker: finalized_attacker, defender: finalized_defender}
  end

  defp finalize_attacker(attacker, defender) do
    %{
      attacker
      | current_hp: Helper.calculate_final_hp(attacker),
        last_hp: Helper.calculate_final_hp(attacker),
        current_mp: Helper.calculate_final_mp(attacker),
        armor: Helper.total_armor(attacker),
        power: Helper.final_power(attacker, defender)
    }
  end

  defp finalize_defender(defender) do
    %{
      defender
      | current_hp: Helper.calculate_final_hp(defender),
        current_mp: Helper.calculate_final_mp(defender),
        armor: Helper.total_armor(defender),
        power: Helper.total_power(defender)
    }
  end

  defp apply_buff(%{attacker: attacker} = turn, buff, duration) when duration > 0 do
    resource = %{buff | buff: true}

    turn
    |> Map.put(:attacker, %{attacker | buffs: tick_buff_duration(attacker.buffs, buff)})
    |> apply_resource(resource)
    |> Map.put(:resource, %{buff | buff: nil})
  end

  defp apply_buff(turn, _, _), do: turn

  defp apply_debuff(%{defender: defender} = turn, debuff, duration) when duration > 0 do
    resource = %{debuff | debuff: true}

    turn
    |> Map.put(:defender, %{defender | debuffs: tick_buff_duration(defender.debuffs, debuff)})
    |> apply_resource(resource)
    |> Map.put(:resource, %{debuff | debuff: nil})
  end

  defp apply_debuff(turn, _, _), do: turn

  defp apply_defender_buff(%{defender: defender} = turn, buff, duration) when duration > 0 do
    resource = %{buff | defender_buff: true}

    turn
    |> Map.put(:defender, %{defender | defender_buffs: tick_buff_duration(defender.defender_buffs, buff)})
    |> apply_resource(resource)
    |> Map.put(:resource, %{buff | defender_buff: nil})
  end

  defp apply_defender_buff(turn, _, _), do: turn

  # Updates a buff, reducing its duration by 1
  defp tick_buff_duration(list, resource) do
    existing =
      %{resource: buff, duration: duration} =
      Enum.find(list, fn %{resource: buff, duration: _} ->
        buff.code == resource.code
      end)

    List.delete(list, existing) ++ [%{resource: buff, duration: duration - 1}]
  end

  # If the attacker has a current double_skill, it is the one that gets cast
  defp use_skill(%{attacker: %{double_skill: double_skill} = attacker} = turn)
       when double_skill != nil do
    %{turn | attacker: attacker, resource: double_skill, skill: double_skill}
    |> apply_spell()
  end

  # Uses a skill from the pre-defined skill_order, this happens when defending
  # in the Arena or when the opponent is an A.I. player.
  defp use_skill(%{attacker: attacker, orders: %{auto: true}} = turn) do
    skill = get_resource_from_order(attacker.skill_order, attacker)
    (skill && cast_skill(turn, skill)) || basic_attack(turn)
  end

  # Uses a basic_attack if the attacker cannot use the skill it was ordered to
  defp use_skill(%{attacker: attacker, orders: %{skill: skill}} = turn) do
    if skill && !skill.passive && Helper.can_use?(attacker, skill, :active) do
      cast_skill(turn, skill)
    else
      basic_attack(turn)
    end
  end

  # A basic_attack (punch icon) deals the attackers atk stat as 'normal' damage
  # This does not cost MP and does not have a cooldown.
  defp basic_attack(turn) do
    basic_attack = Moba.basic_attack()

    %{turn | resource: basic_attack, skill: basic_attack}
    |> Effect.damage_type(Moba.damage_types().normal)
    |> Effect.atk_damage()
    |> Effect.remove_last_skill()
  end

  # Uses an item from the pre-defined item_order, this happens when defending
  # in the Arena or when the opponent is an A.I. player.
  defp use_item(%{attacker: attacker, orders: %{auto: true}} = turn) do
    item = get_resource_from_order(attacker.item_order, attacker)
    (item && cast_item(item, turn)) || turn
  end

  # Uses an item that was ordered by the UI.
  defp use_item(%{attacker: attacker, orders: %{item: item}} = turn) do
    if item && item.active && Helper.can_use?(attacker, item, :active) do
      cast_item(item, turn)
    else
      turn
    end
  end

  # Casts an active Item. Like Skills, some have cooldowns and mp_costs
  defp cast_item(item, turn) do
    Logger.info("Item cast: #{item.code}")

    %{turn | resource: item, item: item}
    |> apply_spell()
    |> Effect.mp_cost()
    |> Effect.add_cooldown()
  end

  defp use_passives(turn, %{owner: owner} = opts) do
    turn
    |> use_passive_resources(owner.passive_skills, opts)
    |> use_passive_resources(owner.passive_items, opts)
  end

  defp use_passive_resources(turn, spells, %{owner: owner} = opts) do
    spells
    |> Enum.reduce(turn, fn resource, acc ->
      if Helper.can_use?(owner, resource, :passive) do
        %{acc | resource: resource} |> apply_spell(opts)
      else
        acc
      end
    end)
  end

  # Applies the current resource in the turn and immediately activates any buffs or
  # debuffs that may have been added by it (Moba.Engine.Core.Effect#add_buff for example)
  defp apply_spell(turn, opts \\ nil) do
    turn
    |> Spell.apply(opts)
    |> maybe_apply_buff()
    |> maybe_apply_debuff()
  end

  defp maybe_apply_buff(%{resource: %{duration: duration, buff: true} = resource} = turn) do
    turn
    |> apply_buff(resource, duration)
  end

  defp maybe_apply_buff(turn), do: turn

  defp maybe_apply_debuff(%{resource: %{duration: duration, debuff: true} = resource} = turn) do
    turn
    |> apply_debuff(resource, duration)
  end

  defp maybe_apply_debuff(turn), do: turn

  defp apply_final_resource(turn, resource) do
    apply_resource(turn, %{resource | final: true})
  end

  defp apply_resource(turn, resource) do
    %{turn | resource: resource}
    |> Spell.apply()
  end

  defp get_resource_from_order(order, battler) do
    order
    |> Enum.filter(fn resource ->
      resource && Helper.can_use?(battler, resource, :active)
    end)
    |> Enum.take(1)
    |> List.first()
  end
end
