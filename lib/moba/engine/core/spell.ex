defmodule Moba.Engine.Core.Spell do
  @moduledoc """
  Handles the chains of both active and passive effects for each Skill and Item, defined by codes

  Certain Spells have special modifiers:
   - double_skill: spell is applied in two consecutive turns, hero cannot cast another until it finishes
   - delayed_skill: spell is cast on the first turn but applied on the next, hero can cast another next turn
   - permanent_skill: spell is applied every turn until set otherwise
   - buff: spell is applied on the attacker every turn until the duration ends (positive fx)
   - debuff: spell is applied on the defender every turn until the duration ends (negative fx)
   - defender_buff: spell is applied on the defener every turn until the duration ends (positive fx)
   - final: spell is applied at the end of the turn (after buffs and reductions are applied)
  """

  alias Moba.{Game, Engine}
  alias Game.Schema.{Skill, Item}
  alias Engine.Core
  alias Core.{Effect, Helper, Processor}

  def apply(turn, options \\ nil) do
    turn
    |> effects_for(options)
  end

  # ACTIVES

  def effects_for(%{resource: %Skill{code: code}, attacker: %{double_skill: nil}} = turn)
      when code == "blade_fury" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.add_next_armor()
    |> Effect.add_double_skill()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "blade_fury" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.add_next_armor()
    |> Effect.remove_double_skill()
  end

  def effects_for(%{resource: %Skill{code: code}, attacker: attacker} = turn) when code == "blink_strike" do
    if Helper.used_skill?(attacker, code) do
      turn
      |> Effect.base_amount_damage()
      |> Effect.other_atk_damage()
      |> Effect.attacker_extra()
    else
      turn
      |> Effect.base_damage()
      |> Effect.atk_damage()
    end
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "death_pulse" do
    turn
    |> Effect.base_damage()
    |> Effect.hp_regen_by_base_amount()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "decay" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.hp_regen_by_atk()
    |> Effect.hp_regen_by_base_amount()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "double_edge" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.self_atk_damage()
  end

  def effects_for(%{resource: %Skill{code: code}, attacker: %{double_skill: nil}} = turn)
      when code == "echo_stomp" do
    turn
    |> Effect.add_double_skill()
    |> Effect.charging()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "echo_stomp" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.remove_double_skill()
  end

  def effects_for(%{resource: %Skill{code: code, buff: nil}} = turn) when code == "empower" do
    turn
    |> Effect.add_buff()
    |> Effect.base_damage()
    |> Effect.atk_damage()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "empower" do
    turn
    |> Effect.add_turn_power()
  end

  def effects_for(%{resource: %Skill{code: code}, attacker: %{double_skill: nil}} = turn)
      when code == "illuminate" do
    turn
    |> Effect.add_double_skill()
    |> Effect.charging()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "illuminate" do
    turn
    |> Effect.base_damage()
    |> Effect.remove_double_skill()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "lightning_bolt" do
    turn
    |> Effect.base_damage()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "maledict" do
    turn
    |> Effect.add_next_power_magic()
    |> Effect.base_damage()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "mana_burn" do
    turn
    |> Effect.base_damage()
    |> Effect.mp_burn_by_defender_total_mp()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "mana_shield" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.add_next_armor_by_total_mp()
  end

  def effects_for(%{resource: %Skill{code: code, buff: nil, debuff: nil}} = turn) when code == "shadow_word" do
    turn
    |> roll(
      fn turn -> Effect.add_buff(turn) end,
      fn turn -> Effect.add_debuff(turn) end
    )
  end

  def effects_for(%{resource: %Skill{code: code, buff: nil}} = turn) when code == "shadow_word" do
    turn
    |> Effect.base_damage()
  end

  def effects_for(%{resource: %Skill{code: code, debuff: nil}} = turn) when code == "shadow_word" do
    turn
    |> Effect.hp_regen_by_base_amount()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "shuriken_toss" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.pierce_turn_armor()
  end

  def effects_for(%{resource: %Skill{code: code, debuff: nil, buff: nil}} = turn) when code == "static_link" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.add_debuff()
    |> Effect.add_buff()
  end

  def effects_for(%{resource: %Skill{code: code, debuff: nil}} = turn) when code == "static_link" do
    turn
    |> Effect.add_turn_atk()
  end

  def effects_for(%{resource: %Skill{code: code, buff: nil}} = turn) when code == "static_link" do
    turn
    |> Effect.remove_turn_atk()
  end

  # ULTIMATES

  def effects_for(%{resource: %Skill{code: code}, attacker: %{double_skill: nil}} = turn)
      when code == "assassinate" do
    turn
    |> Effect.add_double_skill()
    |> Effect.charging()
    |> roll(
      fn turn -> turn |> Effect.attacker_inneffectability() end,
      fn turn -> turn end
    )
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "assassinate" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.remove_double_skill()
  end

  def effects_for(%{resource: %Skill{code: code, buff: nil}} = turn) when code == "bad_juju" do
    turn
    |> Effect.add_buff()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "bad_juju" do
    turn
    |> Effect.add_battle_armor()
    |> Effect.add_battle_power()
  end

  def effects_for(%{resource: %Skill{code: code, defender_buff: nil}} = turn) when code == "borrowed_time" do
    turn
    |> Effect.invulnerability()
    |> Effect.add_defender_buff()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "borrowed_time" do
    turn
    |> Effect.hp_regen_by_damage_taken()
  end

  def effects_for(%{resource: %Skill{code: code} = resource, defender: defender} = turn)
      when code == "culling_blade" do
    if defender.current_hp <= defender.total_hp * resource.extra_multiplier do
      turn |> Effect.execute()
    else
      turn |> Effect.atk_damage() |> Effect.base_damage()
    end
  end

  def effects_for(%{resource: %Skill{code: code, debuff: nil}} = turn) when code == "doom" do
    turn
    |> Effect.add_debuff()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "doom" do
    turn
    |> Effect.silence()
    |> Effect.base_damage()
  end

  def effects_for(%{resource: %Skill{code: code}, attacker: %{delayed_skill: nil}} = turn)
      when code == "dream_coil" do
    turn
    |> Effect.add_delayed_skill()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "dream_coil" do
    turn
    |> Effect.base_damage()
    |> Effect.stun()
  end

  def effects_for(%{resource: %Skill{code: code, buff: nil}} = turn) when code == "elder_dragon_form" do
    turn
    |> Effect.add_buff()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "elder_dragon_form" do
    turn
    |> Effect.base_damage()
    |> Effect.add_turn_power()
    |> Effect.hp_regen_by_base_amount()
  end

  def effects_for(%{resource: %Skill{code: code, buff: nil}} = turn) when code == "gods_strength" do
    turn
    |> Effect.add_buff()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "gods_strength" do
    turn
    |> Effect.add_next_power_normal()
  end

  def effects_for(%{resource: %Skill{code: code, buff: nil}} = turn) when code == "guardian_angel" do
    turn
    |> Effect.add_buff()
    |> Effect.atk_damage()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "guardian_angel" do
    turn
    |> Effect.hp_regen_by_base_amount()
    |> Effect.physical_invulnerability()
    |> Effect.attacker_inneffectability()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "laguna_blade" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.damage_type(Moba.damage_types()[:pure])
    |> Effect.null_armor()
  end

  def effects_for(%{resource: %Skill{code: code}, attacker: %{double_skill: nil}} = turn)
      when code == "life_drain" do
    turn
    |> Effect.base_damage()
    |> Effect.add_double_skill()
    |> Effect.hp_regen_by_total_mp()
    |> Effect.hp_regen_by_base_amount()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "life_drain" do
    turn
    |> Effect.base_damage()
    |> Effect.hp_regen_by_total_mp()
    |> Effect.hp_regen_by_base_amount()
    |> Effect.remove_double_skill()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "omnislash" do
    turn
    |> roll(
      fn turn -> turn |> Effect.attacker_extra() |> Effect.base_damage() |> Effect.other_atk_damage() end,
      fn turn -> turn |> Effect.base_damage() |> Effect.random_atk_damage() end
    )
  end

  def effects_for(%{resource: %Skill{code: code, debuff: nil}, attacker: %{permanent_skill: nil}} = turn)
      when code == "psionic_trap" do
    turn
    |> Effect.add_permanent_skill()
  end

  def effects_for(%{resource: %Skill{code: code, debuff: nil}} = turn) when code == "psionic_trap" do
    turn
    |> roll(
      fn turn -> turn |> Effect.add_debuff() |> Effect.remove_permanent_skill() end,
      fn turn -> turn end
    )
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "psionic_trap" do
    turn
    |> Effect.base_damage()
    |> Effect.pierce_turn_armor()
    |> Effect.remove_turn_atk_by_multiplier()
  end

  def effects_for(%{resource: %Skill{code: code} = resource, attacker: attacker} = turn) when code == "rearm" do
    turn = Effect.reset_cooldowns(turn)
    last_skill = attacker.last_skill

    if last_skill && last_skill.code != code && attacker.current_mp >= last_skill.mp_cost do
      turn = Processor.cast_skill(turn, last_skill)

      %{turn | resource: resource, skill: resource}
      |> Effect.attacker_bonus(last_skill.name)
    else
      Effect.atk_damage(turn)
    end
  end

  def effects_for(%{resource: %Skill{code: code}, attacker: %{delayed_skill: nil}} = turn)
      when code == "remote_mines" do
    turn
    |> Effect.add_delayed_skill()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "remote_mines" do
    turn
    |> Effect.base_damage()
    |> Effect.total_mp_damage()
  end

  def effects_for(%{resource: %Skill{code: code} = resource, defender: defender} = turn)
      when code == "spell_steal" do
    skill = defender.last_skill

    if skill && skill != resource do
      turn =
        turn
        |> Effect.add_turn_power()
        |> Effect.add_next_power()
        |> Processor.cast_skill(skill)

      %{turn | resource: resource, skill: resource}
      |> Effect.attacker_bonus(skill.name)
    else
      turn |> Effect.atk_damage()
    end
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "time_lapse" do
    turn
    |> Effect.reset_hp_to_last_turn()
    |> Effect.damage_by_last_damage_caused()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "walrus_punch" do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.stun()
    |> Effect.damage_type(Moba.damage_types()[:normal])
  end

  # PASSIVES

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "counter_helix" do
    turn
    |> Effect.self_base_damage()
  end

  def effects_for(%{resource: %Skill{code: code}} = turn, %{is_attacking: false})
      when code == "counter_helix" do
    turn
    |> roll(
      fn turn -> effects_for(turn) end,
      fn turn -> turn end
    )
  end

  def effects_for(%{resource: %Skill{code: code}, defender: defender} = turn, %{is_attacking: true})
      when code == "feast" do
    if Helper.normal_damage?(defender) do
      turn
      |> Effect.hp_regen_by_base_amount()
      |> Effect.hp_regen_by_atk()
    else
      turn
    end
  end

  def effects_for(%{resource: %Skill{code: code}, defender: defender} = turn, %{is_attacking: true})
      when code == "fiery_soul" do
    if Helper.magic_damage?(defender) do
      turn |> Effect.add_battle_power()
    else
      turn
    end
  end

  def effects_for(%{resource: %Skill{code: code}} = turn) when code == "fury_swipes" do
    Effect.base_damage(turn)
  end

  def effects_for(%{resource: %Skill{code: code}, defender: defender} = turn, %{is_attacking: true})
      when code == "fury_swipes" do
    if Helper.normal_damage?(defender) do
      turn
      |> Effect.refresh_debuff()
      |> Effect.add_debuff()
    else
      turn
    end
  end

  def effects_for(%{resource: %Skill{code: code}, defender: defender} = turn, %{is_attacking: true})
      when code == "jinada" do
    if Helper.normal_damage?(defender) do
      turn
      |> Effect.add_turn_power()
      |> Effect.base_damage()
    else
      turn
    end
  end

  def effects_for(%{resource: %Skill{code: code}} = turn, %{
        is_attacking: false
      })
      when code == "phase_shift" do
    turn
    |> roll(
      fn turn ->
        turn |> Effect.defender_invulnerability() |> Effect.defender_mp_cost() |> Effect.add_defender_cooldown()
      end,
      fn turn -> turn end
    )
  end

  # ULTIMATES

  def effects_for(%{resource: %Skill{code: code} = resource, defender: defender, attacker: attacker} = turn, %{
        is_attacking: false
      })
      when code == "battle_trance" do
    result = defender.current_hp - Helper.calculate_final_defender_damage(attacker, defender)

    if result / defender.total_hp * 100 <= resource.base_amount do
      turn
      |> Effect.limit_defender_hp_to_base_amount()
      |> Effect.defender_mp_cost()
      |> Effect.add_defender_battle_armor()
      |> Effect.add_defender_battle_power()
      |> Effect.add_defender_cooldown()
    else
      turn
    end
  end

  def effects_for(%{resource: %Skill{code: code} = resource, attacker: attacker} = turn, %{is_attacking: true})
      when code == "battle_trance" do
    result = attacker.current_hp - attacker.damage

    if result / attacker.total_hp * 100 <= resource.base_amount do
      turn
      |> Effect.limit_attacker_hp_to_base_amount()
      |> Effect.mp_cost()
      |> Effect.add_battle_armor()
      |> Effect.add_battle_power()
      |> Effect.add_cooldown()
    else
      turn
    end
  end

  def effects_for(%{resource: %Skill{code: code}} = turn, %{is_attacking: true})
      when code == "coup" do
    turn
    |> roll(
      fn turn -> turn |> Effect.add_turn_power() end,
      fn turn -> turn end
    )
  end

  # ITEMS

  def effects_for(turn, nil), do: effects_for(turn)

  # BASIC

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: true})
      when code == "ring_of_tarrasque" do
    turn
    |> Effect.hp_regen_by_base_amount()
  end

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: true})
      when code == "sages_mask" do
    turn
    |> Effect.mp_regen_by_base_amount()
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "magic_stick" do
    turn
    |> Effect.hp_regen_by_base_amount()
    |> Effect.mp_regen_by_extra_amount()
  end

  # RARE

  def effects_for(%{resource: %Item{code: code}, number: turn_number} = turn, %{
        is_attacking: true
      })
      when code == "shadow_blade" and turn_number == 1 do
    turn
    |> Effect.base_amount_damage()
  end

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: true})
      when code == "crystalys" do
    turn
    |> roll(
      fn turn -> turn |> Effect.add_turn_power() |> Effect.add_cooldown() end,
      fn turn -> turn end
    )
  end

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: false})
      when code == "vanguard" do
    turn
    |> roll(
      fn turn -> turn |> Effect.block_damage() end,
      fn turn -> turn end
    )
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "pipe_of_insight" do
    turn
    |> Effect.add_next_armor()
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "tranquil_boots" do
    turn
    |> Effect.hp_regen_by_base_amount()
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "arcane_boots" do
    turn
    |> Effect.mp_regen_by_base_amount()
  end

  # EPIC

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: true})
      when code == "assault_cuirass" do
    turn
    |> Effect.pierce_turn_armor()
  end

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: true})
      when code == "diffusal_blade" do
    turn
    |> Effect.mp_burn_by_defender_total_mp()
    |> Effect.damage_by_defender_total_mp()
  end

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: true})
      when code == "maelstrom" do
    turn
    |> roll(
      fn turn -> turn |> Effect.base_amount_damage() end,
      fn turn -> turn end
    )
  end

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: true})
      when code == "mkb" do
    turn
    |> roll(
      fn turn -> turn |> Effect.void_invulnerability() |> Effect.null_armor() end,
      fn turn -> turn end
    )
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "dagon" or code == "dagon5" do
    turn
    |> Effect.base_amount_damage()
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "heavens_halberd" do
    turn
    |> Effect.disarm()
  end

  def effects_for(%{resource: %{code: code, defender_buff: nil}} = turn) when code == "bkb" do
    turn
    |> Effect.attacker_extra()
    |> Effect.add_defender_buff()
  end

  def effects_for(%{resource: %{code: code}} = turn) when code == "bkb" do
    turn
    |> Effect.inneffectability()
  end

  # LEGENDARY

  def effects_for(%{resource: %Item{code: code}, number: turn_number} = turn, %{
        is_attacking: true
      })
      when code == "silver_edge" and turn_number == 1 do
    turn
    |> Effect.base_amount_damage()
  end

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: true})
      when code == "daedalus" do
    turn
    |> roll(
      fn turn -> turn |> Effect.add_turn_power() end,
      fn turn -> turn end
    )
  end

  def effects_for(%{resource: %Item{code: code}} = turn, %{is_attacking: true})
      when code == "radiance" do
    turn
    |> Effect.atk_damage()
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "scythe_of_vyse" do
    turn
    |> Effect.stun()
  end

  def effects_for(%{resource: %Item{code: code, final: true}} = turn) when code == "satanic" do
    turn
    |> Effect.damage_regen()
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "satanic" do
    turn
    |> Effect.add_to_final()
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "shivas_guard" do
    turn
    |> Effect.add_next_armor()
    |> Effect.base_amount_damage()
  end

  def effects_for(%{resource: %Item{code: code}} = turn) when code == "orchid_malevolence" do
    turn
    |> Effect.pierce_turn_armor()
    |> Effect.silence()
  end

  def effects_for(%{resource: %Item{code: code}, defender: defender} = turn, %{is_attacking: false})
      when code == "linkens_sphere" do
    if Helper.disabled?(defender) do
      turn
      |> Effect.inneffectability()
      |> Effect.add_defender_cooldown()
      |> Effect.mp_cost()
    else
      turn
    end
  end

  def effects_for(turn) do
    turn
  end

  def effects_for(turn, _) do
    turn
  end

  defp first_turn_roll(
         %{resource: resource, number: turn_number} = turn,
         success,
         failure
       ) do
    roll_number = if turn_number == 1, do: resource.extra_amount, else: resource.roll_number
    roll(turn, success, failure, roll_number)
  end

  defp roll(%{resource: resource} = turn, success, failure, roll_number \\ nil) do
    number = roll_number || resource.roll_number

    if number >= Enum.random(0..100) do
      success.(turn)
    else
      failure.(turn)
    end
  end
end
