defmodule Moba.Engine.Core.Effect do
  @moduledoc """
  Modular functions that can be chained together by Spells or the Processor to
  apply battle effects that can manipulate properties of a Battler.
  """

  # BASE DAMAGE

  def base_damage(%{resource: %{base_damage: base_damage}} = turn) do
    update_defender_number(turn, :damage, base_damage)
  end

  def base_amount_damage(%{resource: %{base_amount: base_amount}} = turn) do
    update_defender_number(turn, :damage, base_amount)
  end

  def block_damage(%{resource: resource} = turn) do
    update_defender_number(turn, :damage, -(resource.base_amount || 0))
  end

  def self_base_damage(%{resource: %{base_damage: base_damage}} = turn) do
    update_attacker_number(turn, :damage, base_damage)
  end

  # ATK DAMAGE

  def atk_damage(%{attacker: attacker, resource: resource} = turn) do
    update_defender_number(turn, :damage, attacker.atk * resource.atk_multiplier)
  end

  def other_atk_damage(%{attacker: attacker, resource: resource} = turn) do
    update_defender_number(turn, :damage, attacker.atk * resource.other_atk_multiplier)
  end

  def random_atk_damage(%{attacker: attacker, resource: resource} = turn) do
    start = trunc(resource.atk_multiplier * 100)
    endd = trunc(resource.other_atk_multiplier * 100)

    multiplier = Enum.random(start..endd) / 100

    update_defender_number(turn, :damage, attacker.atk * multiplier)
  end

  def self_atk_damage(%{attacker: attacker, resource: resource} = turn) do
    update_attacker_number(turn, :damage, attacker.atk * resource.other_atk_multiplier)
  end

  # HP DAMAGE

  def total_hp_damage(%{attacker: attacker, resource: resource} = turn) do
    update_defender_number(turn, :damage, attacker.total_hp * resource.hp_multiplier)
  end

  def current_hp_damage(%{attacker: attacker, resource: resource} = turn) do
    update_defender_number(turn, :damage, attacker.current_hp * resource.hp_multiplier)
  end

  def damage_by_defender_current_hp(%{defender: defender, resource: resource} = turn) do
    update_defender_number(turn, :damage, defender.current_hp * resource.hp_multiplier)
  end

  def damage_by_defender_total_hp(%{defender: defender, resource: resource} = turn) do
    update_defender_number(turn, :damage, defender.total_hp * resource.hp_multiplier)
  end

  def self_damage_by_defender_total_hp(%{defender: defender, resource: resource} = turn) do
    update_attacker_number(turn, :damage, defender.total_hp * resource.hp_multiplier)
  end

  def self_current_hp_damage(%{attacker: attacker, resource: resource} = turn) do
    update_attacker_number(turn, :damage, attacker.current_hp * resource.other_hp_multiplier)
  end

  def damage_by_missing_hp(%{attacker: attacker, resource: resource} = turn) do
    missing = attacker.total_hp - attacker.current_hp
    update_defender_number(turn, :damage, missing * resource.hp_multiplier)
  end

  # MP DAMAGE

  def total_mp_damage(%{attacker: attacker, resource: resource} = turn) do
    update_defender_number(turn, :damage, attacker.total_mp * resource.mp_multiplier)
  end

  def damage_by_defender_total_mp(%{defender: defender, resource: resource} = turn) do
    update_defender_number(turn, :damage, defender.total_mp * resource.mp_multiplier)
  end

  # HP REGEN

  def add_hp_steal_by_defender_current_hp(%{defender: defender, resource: resource} = turn) do
    update_attacker_number(turn, :hp_steal, resource.hp_regen_multiplier * defender.current_hp)
  end

  def extra_hp_regen(%{resource: resource} = turn) do
    update_attacker_number(turn, :hp_regen, resource.extra_amount)
  end

  def hp_regen_by_base_amount(%{resource: resource} = turn) do
    update_attacker_number(turn, :hp_regen, resource.base_amount)
  end

  def hp_regen_by_atk(%{attacker: attacker, resource: resource} = turn) do
    update_attacker_number(turn, :hp_regen, attacker.atk * resource.hp_regen_multiplier)
  end

  def hp_regen_by_total_hp(%{attacker: attacker, resource: resource} = turn) do
    update_attacker_number(turn, :hp_regen, attacker.total_hp * resource.hp_regen_multiplier)
  end

  def hp_regen_by_total_mp(%{attacker: attacker, resource: resource} = turn) do
    update_attacker_number(turn, :hp_regen, attacker.total_mp * resource.hp_regen_multiplier)
  end

  def total_hp_cost(%{attacker: attacker, resource: resource} = turn) do
    update_attacker_number(turn, :current_hp, -(attacker.total_hp * resource.other_hp_multiplier))
  end

  def hp_regen_by_missing_hp(%{attacker: attacker, resource: resource} = turn) do
    missing = attacker.total_hp - attacker.current_hp
    update_attacker_number(turn, :hp_regen, missing * resource.hp_multiplier)
  end

  def hp_regen_by_damage_taken(%{defender: defender, resource: resource} = turn) do
    update_defender_number(turn, :hp_regen, defender.damage * resource.hp_regen_multiplier)
  end

  def damage_regen(%{defender: defender, resource: resource} = turn) do
    update_attacker_number(turn, :hp_regen, defender.damage * resource.hp_regen_multiplier)
  end

  def cut_hp_regen(%{attacker: %{hp_regen: regen} = attacker, resource: resource} = turn) when regen > 0 do
    update_attacker_number(turn, :hp_regen, -(attacker.hp_regen * resource.hp_regen_multiplier))
  end

  def cut_hp_regen(turn), do: turn

  # MP REGEN

  def mp_regen_by_base_amount(%{resource: resource} = turn) do
    update_attacker_number(turn, :mp_regen, resource.base_amount)
  end

  def mp_regen_by_extra_amount(%{resource: resource} = turn) do
    update_attacker_number(turn, :mp_regen, resource.extra_amount)
  end

  def defender_mp_cost(%{resource: resource} = turn) do
    update_defender_number(turn, :current_mp, -resource.mp_cost)
  end

  def mp_burn_by_total_mp(%{attacker: attacker, resource: resource} = turn) do
    update_defender_number(turn, :mp_burn, attacker.total_mp * resource.other_mp_multiplier)
  end

  def mp_burn_by_defender_total_mp(%{defender: defender, resource: resource} = turn) do
    update_defender_number(turn, :mp_burn, defender.total_mp * resource.other_mp_multiplier)
  end

  def mp_burn_by_base_amount(%{resource: resource} = turn) do
    update_defender_number(turn, :mp_burn, resource.base_amount)
  end

  def mp_cost(%{resource: resource} = turn) do
    update_attacker_number(turn, :current_mp, -resource.mp_cost)
  end

  def mp_steal_by_defender_total_mp(%{defender: defender, resource: resource} = turn) do
    steal = defender.total_mp * resource.mp_regen_multiplier

    turn
    |> update_attacker_number(:mp_regen, steal)
    |> update_defender_number(:mp_burn, steal)
  end

  def mp_regen_by_total_mp(%{attacker: attacker, resource: resource} = turn) do
    update_attacker_number(turn, :mp_regen, attacker.total_mp * resource.mp_regen_multiplier)
  end

  def turn_mp_regen(%{attacker: attacker} = turn) do
    update_attacker_number(turn, :mp_regen, Float.ceil(attacker.total_mp * Moba.turn_mp_regen_multiplier()))
  end

  # ARMOR

  def add_battle_armor(%{resource: resource} = turn) do
    update_attacker_number(turn, :battle_armor, resource.armor_amount)
  end

  def add_next_armor(%{resource: resource} = turn) do
    update_attacker_number(turn, :next_armor, resource.armor_amount)
  end

  def add_defender_battle_armor(%{resource: resource} = turn) do
    update_defender_number(turn, :battle_armor, resource.armor_amount)
  end

  def add_turn_armor(%{resource: resource} = turn) do
    update_attacker_number(turn, :turn_armor, resource.armor_amount)
  end

  def add_next_armor_by_total_mp(%{attacker: attacker, resource: resource} = turn) do
    update_attacker_number(turn, :next_armor, attacker.total_mp * resource.mp_multiplier)
  end

  def pierce_battle_armor(%{resource: resource} = turn) do
    update_defender_number(turn, :battle_armor, -resource.armor_amount)
  end

  def pierce_turn_armor(%{resource: resource} = turn) do
    update_defender_number(turn, :turn_armor, -resource.armor_amount)
  end

  def remove_turn_armor(%{resource: resource} = turn) do
    update_defender_number(turn, :turn_armor, -resource.armor_amount)
  end

  # POWER

  def add_battle_power(%{resource: resource} = turn) do
    update_attacker_number(turn, :battle_power, resource.power_amount)
  end

  def add_next_power(%{resource: resource} = turn) do
    update_attacker_number(turn, :next_power, resource.power_amount)
  end

  def add_next_power_magic(%{resource: resource} = turn) do
    update_attacker_number(turn, :next_power_magic, resource.power_amount)
  end

  def add_defender_battle_power(%{resource: resource} = turn) do
    update_defender_number(turn, :battle_power, resource.power_amount)
  end

  def add_battle_power_normal(%{resource: resource} = turn) do
    update_attacker_number(turn, :battle_power_normal, resource.power_amount)
  end

  def add_next_power_normal(%{resource: resource} = turn) do
    update_attacker_number(turn, :next_power_normal, resource.power_amount)
  end

  def add_turn_power(%{resource: resource} = turn) do
    update_attacker_number(turn, :turn_power, resource.power_amount)
  end

  def remove_battle_power(%{resource: resource} = turn) do
    update_defender_number(turn, :battle_power, -resource.power_amount)
  end

  def remove_turn_power(%{resource: resource} = turn) do
    update_defender_number(turn, :turn_power, -resource.power_amount)
  end

  def remove_attacker_turn_power(%{resource: resource} = turn) do
    update_attacker_number(turn, :turn_power, -resource.power_amount)
  end

  # ATK

  def add_turn_atk(%{resource: resource} = turn) do
    update_attacker_number(turn, :turn_atk, resource.base_amount)
  end

  def remove_turn_atk(%{resource: resource} = turn) do
    update_defender_number(turn, :turn_atk, -resource.base_amount)
  end

  def remove_turn_atk_by_multiplier(%{resource: resource, defender: defender} = turn) do
    update_defender_number(turn, :turn_atk, -(resource.atk_multiplier * defender.base_atk))
  end

  # STATUS

  def add_to_final(%{resource: resource, final_effects: final_effects} = turn) do
    %{turn | final_effects: final_effects ++ [resource]}
  end

  def add_buff(%{resource: %{duration: duration} = resource, attacker: attacker} = turn) do
    turn
    |> update_attacker(:buffs, attacker.buffs ++ [%{resource: resource, duration: duration}])
    |> Map.put(:resource, %{resource | buff: true})
  end

  def add_debuff(%{resource: %{duration: duration} = resource, defender: defender} = turn) do
    turn
    |> update_defender(:debuffs, defender.debuffs ++ [%{resource: resource, duration: duration}])
    |> Map.put(:resource, %{resource | debuff: true})
  end

  def add_defender_buff(%{resource: %{duration: duration} = resource, attacker: attacker} = turn) do
    turn
    |> update_attacker(:defender_buffs, attacker.defender_buffs ++ [%{resource: resource, duration: duration}])
  end

  def add_attacker_debuff(%{resource: %{duration: duration} = resource, defender: defender} = turn) do
    turn
    |> update_defender(:attacker_debuffs, defender.attacker_debuffs ++ [%{resource: resource, duration: duration}])
  end

  def refresh_debuff(%{resource: %{duration: duration} = resource, defender: defender} = turn) do
    turn
    |> update_defender(
      :debuffs,
      Enum.map(defender.debuffs, fn debuff ->
        if debuff.resource == resource do
          %{resource: resource, duration: duration}
        else
          debuff
        end
      end)
    )
  end

  def dispel_debuffs(turn) do
    turn
    |> update_attacker(:debuffs, [])
  end

  def add_delayed_skill(%{resource: resource} = turn) do
    update_attacker(turn, :delayed_skill, resource)
  end

  def add_double_skill(%{resource: resource} = turn) do
    update_attacker(turn, :double_skill, resource)
  end

  def remove_double_skill(turn) do
    turn
    |> update_attacker(:double_skill, nil)
    |> update_attacker(:charging, false)
  end

  def add_last_skill(%{resource: resource} = turn) do
    update_attacker(turn, :last_skill, resource)
  end

  def remove_last_skill(turn) do
    update_attacker(turn, :last_skill, nil)
  end

  def add_permanent_skill(%{resource: resource} = turn) do
    update_attacker(turn, :permanent_skill, resource)
  end

  def remove_permanent_skill(turn) do
    update_attacker(turn, :permanent_skill, nil)
  end

  def defender_invulnerability(turn) do
    update_defender(turn, :invulnerable, true)
  end

  def damage_type(%{defender: %{damage_type: defender_type}} = turn, type) when defender_type != "pure" do
    update_defender(turn, :damage_type, type)
  end

  def damage_type(turn, _), do: turn

  def physical_invulnerability(turn) do
    update_attacker(turn, :physically_invulnerable, true)
  end

  def invulnerability(turn) do
    update_attacker(turn, :invulnerable, true)
  end

  def void_invulnerability(turn) do
    update_defender(turn, :invulnerable, false)
  end

  def miss(turn) do
    update_defender(turn, :miss, true)
  end

  def null_armor(turn) do
    update_defender(turn, :null_armor, true)
  end

  def void_null_armor(turn) do
    update_defender(turn, :null_armor, false)
  end

  def silence(turn) do
    update_defender(turn, :silenced, true)
  end

  def stun(turn) do
    update_defender(turn, :stunned, true)
  end

  def attacker_inneffectability(turn) do
    update_attacker(turn, :inneffectable, true)
  end

  def inneffectability(turn) do
    update_defender(turn, :inneffectable, true)
  end

  def disarm(turn) do
    update_defender(turn, :disarmed, true)
  end

  def execute(turn) do
    turn
    |> update_defender(:extra, true)
    |> update_defender(:current_hp, 0)
  end

  def charging(turn) do
    update_attacker(turn, :charging, true)
  end

  # EXTRAS

  def extra_damage(%{resource: resource} = turn) do
    update_defender_number(turn, :damage, resource.extra_amount)
  end

  def block_extra_damage(%{resource: resource} = turn) do
    update_defender_number(turn, :damage, -resource.extra_amount)
  end

  def damage_by_last_damage_caused(%{attacker: attacker, resource: resource} = turn) do
    update_defender_number(turn, :damage, attacker.last_damage_caused * resource.extra_multiplier)
  end

  def damage_by_last_damage_taken(%{attacker: attacker, resource: resource} = turn) do
    update_defender_number(turn, :damage, attacker.last_damage_taken * resource.extra_multiplier)
  end

  def reset_hp_to_last_turn(%{attacker: attacker} = turn) do
    update_attacker(turn, :current_hp, attacker.last_hp)
  end

  def reflect_damage(%{defender: defender, resource: resource} = turn) do
    update_attacker_number(turn, :damage, defender.damage * resource.extra_multiplier)
  end

  def add_cooldown(%{attacker: attacker, resource: resource} = turn) do
    %{
      turn
      | attacker: %{
          attacker
          | future_cooldowns: Map.put(attacker.future_cooldowns, resource.code, resource.cooldown || 1)
        }
    }
  end

  def add_defender_cooldown(%{defender: defender, resource: resource} = turn) do
    %{
      turn
      | defender: %{
          defender
          | future_cooldowns: Map.put(defender.future_cooldowns, resource.code, resource.cooldown || 1)
        }
    }
  end

  def reset_cooldowns(%{attacker: attacker} = turn) do
    %{turn | attacker: %{attacker | future_cooldowns: %{}}}
  end

  def attacker_extra(turn) do
    update_attacker(turn, :extra, true)
  end

  def attacker_bonus(turn, bonus) do
    if bonus, do: update_attacker(turn, :bonus, bonus), else: turn
  end

  def limit_attacker_hp_to_base_amount(%{resource: resource, attacker: attacker} = turn) do
    limit = round(attacker.total_hp * resource.base_amount / 100)

    turn
    |> update_attacker(:current_hp, limit)
    |> update_attacker(:damage, 0)
  end

  def limit_defender_hp_to_base_amount(%{resource: resource, defender: defender} = turn) do
    limit = round(defender.total_hp * resource.base_amount / 100)

    turn
    |> update_defender(:current_hp, limit)
    |> update_defender(:damage, 0)
  end

  def increment_spell_count(%{attacker: attacker} = turn) do
    update_attacker(turn, :spell_count, attacker.spell_count + 1)
  end

  def spell_count_base_damage(%{attacker: attacker, resource: resource} = turn) do
    update_defender_number(turn, :damage, attacker.spell_count * resource.base_damage)
  end

  def disarmed(turn) do
    %{turn | resource: %{code: "disarmed", name: "Disarmed"}}
    |> update_attacker(:extra, true)
  end

  def invulnerable(turn) do
    %{turn | resource: %{code: "invulnerable", name: "Invulnerable"}}
    |> update_defender(:extra, true)
  end

  # HELPERS

  defp update_attacker_number(%{attacker: attacker} = turn, key, value) do
    update_attacker(turn, key, Map.get(attacker, key) + (value || 0), value || 0)
  end

  defp update_defender_number(%{defender: defender} = turn, key, value) do
    update_defender(turn, key, Map.get(defender, key) + (value || 0), value || 0)
  end

  # All effects ultimately boil down to these two functions, which stores all effects in a list
  # that will then be grouped and translated by Moba.Engine.Core.Logger
  #  - key: things like damage, hp_regen, mp_regen
  #  - value: numbers or booleans
  #  - resource: code of whatever resource triggered the effect
  #  - priority: where it should show up in the description list, lower numbers show first
  defp update_attacker(
         %{attacker: attacker, resource: resource} = turn,
         key,
         value,
         increment \\ true
       ) do
    attacker = %{
      attacker
      | effects:
          attacker.effects ++
            [
              %{
                "key" => key,
                "value" => effect_value(value, increment),
                "resource" => resource.code,
                "priority" => priority_for(turn, resource)
              }
            ]
    }

    %{turn | attacker: Map.put(attacker, key, round_number(value))}
  end

  defp update_defender(
         %{defender: defender, resource: resource} = turn,
         key,
         value,
         increment \\ true
       ) do
    defender = %{
      defender
      | effects:
          defender.effects ++
            [
              %{
                "key" => key,
                "value" => effect_value(value, increment),
                "resource" => resource.code,
                "priority" => priority_for(turn, resource)
              }
            ]
    }

    %{turn | defender: Map.put(defender, key, round_number(value))}
  end

  defp round_number(value) when is_integer(value) or is_float(value) do
    round(value)
  end

  defp round_number(value) do
    value
  end

  defp effect_value(_, increment) when is_integer(increment) or is_float(increment) do
    round(increment)
  end

  defp effect_value(value, increment) when is_boolean(increment) do
    logged_value(value)
  end

  defp effect_value(_, increment) do
    increment
  end

  defp logged_value(value) when is_list(value) do
    Enum.map(value, fn %{resource: buff, duration: _} -> buff.code end) |> Enum.join(", ")
  end

  defp logged_value(value) when is_map(value) do
    value.code
  end

  defp logged_value(value) do
    value || "false"
  end

  defp priority_for(turn, resource) do
    struct = Map.get(resource, :__struct__)

    cond do
      resource == turn.skill -> 1
      resource == turn.item -> 2
      struct == Moba.Game.Schema.Skill -> 3
      struct == Moba.Game.Schema.Item -> 4
      true -> 5
    end
  end
end
