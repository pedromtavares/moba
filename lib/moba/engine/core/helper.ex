defmodule Moba.Engine.Core.Helper do
  @moduledoc """
  Core convenience functions and calculations for Battlers
  """

  @doc """
  Makes sure a Battler has MP (case the spell requires one) and that
  the specified resource is not on cooldown (if it has one)
  """
  def can_use?(_, nil, _), do: false

  def can_use?(battler, resource, type) do
    resources =
      if type == :active do
        battler.active_skills ++ battler.active_items
      else
        battler.passive_skills ++ battler.passive_items
      end

    codes = resources |> Enum.map(& &1.code)
    cooldown = battler.cooldowns[resource.code]

    Enum.member?(codes, resource.code) &&
      (is_nil(resource.mp_cost) || battler.current_mp >= resource.mp_cost) &&
      (is_nil(cooldown) || cooldown + 1 <= 0)
  end

  def alive?(battler), do: battler.current_hp > 0

  def dead?(battler), do: not alive?(battler)

  def disabled?(battler), do: battler.stunned || battler.silenced

  def used_skill?(battler, skill_code) do
    Enum.find(battler.cooldowns, fn {code, _} -> code == skill_code end)
  end

  def calculate_damage_buff(attacker, defender) do
    total = final_power(attacker, defender)

    if total > 0, do: total / 100, else: 0
  end

  @doc """
  The amount of Power applied will depend on the damage type dealt to the defender
  """
  def final_power(attacker, defender) do
    if normal_damage?(defender) do
      total_power_normal(attacker)
    else
      total_power_magic(attacker)
    end
  end

  def total_power(battler) do
    battler.base_power + battler.battle_power + battler.turn_power - battler.purged_power
  end

  def total_power_magic(battler) do
    total_power(battler) + battler.turn_power_magic + battler.battle_power_magic
  end

  def total_power_normal(battler) do
    total_power(battler) + battler.turn_power_normal + battler.battle_power_normal
  end

  def normal_damage?(battler), do: battler.damage_type == Moba.damage_types().normal

  def magic_damage?(battler), do: not normal_damage?(battler)

  def calculate_damage_reduction(%{null_armor: true}), do: 0

  def calculate_damage_reduction(defender) do
    armor = total_armor(defender)
    reduction = total_damage_reduction(armor)
    reduction / 100
  end

  def total_armor(battler) do
    battler.base_armor + battler.battle_armor + battler.turn_armor + battler.next_armor
  end

  @doc """
  There are significant diminishing returns the higher Armor a battler has, to make sure
  you can't just go full Armor and avoid all damage.
  """
  def total_damage_reduction(armor) when armor > 50, do: 37.5 + (armor - 50) * 0.1
  def total_damage_reduction(armor) when armor > 25, do: 25 + (armor - 25) * 0.5
  def total_damage_reduction(armor) when armor < 0, do: 0
  def total_damage_reduction(armor), do: armor

  def calculate_final_hp(battler) do
    result =
      battler.current_hp +
        battler.hp_regen -
        battler.damage -
        battler.self_damage

    cond do
      result > battler.total_hp -> battler.total_hp
      true -> round(result)
    end
  end

  def calculate_final_defender_damage(attacker, defender) do
    total_buff = calculate_damage_buff(attacker, defender)
    defender.damage + defender.damage * total_buff
  end

  def calculate_final_mp(battler) do
    result =
      battler.current_mp -
        battler.mp_burn +
        battler.mp_regen

    cond do
      result < 0 -> 0
      result > battler.total_mp -> battler.total_mp
      true -> round(result)
    end
  end

  @doc """
  turn_atk is given by spells like static_link
  """
  def calculate_atk(battler) do
    %{battler | atk: battler.base_atk + battler.turn_atk}
  end
end
