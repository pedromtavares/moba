defmodule Moba.Engine.Core.Spell do
  @moduledoc """
  Handles the chains of both active and passive effects for each Skill and Item, defined by codes

  Certain Spells have special modifiers:
   - double_skill: spell is applied in two consecutive turns, hero cannot cast another until it finishes
   - delayed_skill: spell is cast on the first turn but applied on the next, hero can cast another next turn
   - permanent_skill: spell is applied every turn until set otherwise
   - buff: spell is applied on the attacker every turn until the duration ends (positive fx)
   - debuff: spell is applied on the defender every turn until the duration ends (negative fx)
   - defender_buff: spell is applied on the defender every turn until the duration ends (positive fx)
   - attacker_debuff: spell is applied on the attacker every turn until the duration ends (negative fx)
   - final: spell is applied at the end of the turn (after buffs and reductions are applied)
  """

  alias Moba.{Game, Engine}
  alias Game.Schema.{Skill, Item}
  alias Engine.Core
  alias Core.{Effect, Helper, Processor}

  def apply(turn, options \\ %{}) do
    effects_for(turn, options)
  end

  # ACTIVES

  defp effects_for(%{resource: %Skill{code: "blade_fury"}, attacker: %{double_skill: nil}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.add_next_armor()
    |> Effect.add_double_skill()
  end

  defp effects_for(%{resource: %Skill{code: "blade_fury"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.add_next_armor()
    |> Effect.remove_double_skill()
  end

  defp effects_for(%{resource: %Skill{code: "blink_strike" = code}} = turn, _options) do
    if Helper.used_skill?(turn.attacker, code) do
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

  defp effects_for(%{resource: %Skill{code: "death_pulse"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.hp_regen_by_base_amount()
  end

  defp effects_for(%{resource: %Skill{code: "decay"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.hp_regen_by_atk()
    |> Effect.hp_regen_by_base_amount()
  end

  defp effects_for(%{resource: %Skill{code: "double_edge"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.self_atk_damage()
  end

  defp effects_for(%{resource: %Skill{code: "echo_stomp"}, attacker: %{double_skill: nil}} = turn, _options) do
    turn
    |> Effect.add_double_skill()
    |> Effect.charging()
  end

  defp effects_for(%{resource: %Skill{code: "echo_stomp"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.remove_double_skill()
  end

  defp effects_for(%{resource: %Skill{code: "empower", buff: nil}} = turn, _options) do
    turn
    |> Effect.add_buff()
    |> Effect.base_damage()
    |> Effect.atk_damage()
  end

  defp effects_for(%{resource: %Skill{code: "empower"}} = turn, _options) do
    turn
    |> Effect.add_turn_power()
  end

  defp effects_for(%{resource: %Skill{code: "illuminate"}, attacker: %{double_skill: nil}} = turn, _options) do
    turn
    |> Effect.add_double_skill()
    |> Effect.charging()
  end

  defp effects_for(%{resource: %Skill{code: "illuminate"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.remove_double_skill()
  end

  defp effects_for(%{resource: %Skill{code: "lightning_bolt"}} = turn, _options) do
    turn
    |> Effect.base_damage()
  end

  defp effects_for(%{resource: %Skill{code: "maledict"}} = turn, _options) do
    turn
    |> Effect.add_next_power_magic()
    |> Effect.base_damage()
  end

  defp effects_for(%{resource: %Skill{code: "mana_burn"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.mp_burn_by_defender_total_mp()
  end

  defp effects_for(%{resource: %Skill{code: "mana_shield"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.add_next_armor_by_total_mp()
  end

  defp effects_for(%{resource: %Skill{code: "shadow_word", buff: nil, debuff: nil}} = turn, _options) do
    turn
    |> roll(
      fn turn -> Effect.add_buff(turn) end,
      fn turn -> Effect.add_debuff(turn) end
    )
  end

  defp effects_for(%{resource: %Skill{code: "shadow_word", buff: nil}} = turn, _options) do
    turn
    |> Effect.base_damage()
  end

  defp effects_for(%{resource: %Skill{code: "shadow_word", debuff: nil}} = turn, _options) do
    turn
    |> Effect.hp_regen_by_base_amount()
  end

  defp effects_for(%{resource: %Skill{code: "shuriken_toss"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.pierce_turn_armor()
  end

  defp effects_for(%{resource: %Skill{code: "static_link", debuff: nil, buff: nil}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.add_debuff()
    |> Effect.add_buff()
  end

  defp effects_for(%{resource: %Skill{code: "static_link", debuff: nil}} = turn, _options) do
    turn
    |> Effect.add_turn_atk()
  end

  defp effects_for(%{resource: %Skill{code: "static_link", buff: nil}} = turn, _options) do
    turn
    |> Effect.remove_turn_atk()
  end

  # BOSS

  defp effects_for(%{resource: %Skill{code: "boss_slam"}} = turn, _options) do
    turn
    |> Effect.base_damage()
  end

  defp effects_for(%{resource: %Skill{code: "boss_bash"}} = turn, %{is_attacking: true}) do
    turn
    |> roll(
      fn turn -> turn |> Effect.stun() |> Effect.add_cooldown() end,
      fn turn -> turn end
    )
  end

  defp effects_for(%{resource: %Skill{code: "boss_spell_block"}} = turn, %{is_attacking: false}) do
    if Helper.disabled?(turn.defender) do
      turn
      |> Effect.inneffectability()
      |> Effect.add_defender_cooldown()
    else
      turn
    end
  end

  defp effects_for(%{resource: %Skill{code: "boss_ult"}} = turn, %{is_attacking: true}) do
    turn
    |> Effect.add_battle_armor()
    |> Effect.add_battle_power()
  end

  # ULTIMATES

  defp effects_for(%{resource: %Skill{code: "assassinate"}, attacker: %{double_skill: nil}} = turn, _options) do
    turn
    |> Effect.add_double_skill()
    |> Effect.charging()
    |> roll(
      fn turn -> turn |> Effect.attacker_inneffectability() end,
      fn turn -> turn end
    )
  end

  defp effects_for(%{resource: %Skill{code: "assassinate"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.remove_double_skill()
  end

  defp effects_for(%{resource: %Skill{code: "bad_juju", buff: nil}} = turn, _options) do
    turn
    |> Effect.add_buff()
  end

  defp effects_for(%{resource: %Skill{code: "bad_juju"}} = turn, _options) do
    turn
    |> Effect.add_battle_armor()
    |> Effect.add_battle_power()
  end

  defp effects_for(%{resource: %Skill{code: "borrowed_time", defender_buff: nil}} = turn, _options) do
    turn
    |> Effect.invulnerability()
    |> Effect.add_defender_buff()
  end

  defp effects_for(%{resource: %Skill{code: "borrowed_time"}} = turn, _options) do
    turn
    |> Effect.hp_regen_by_damage_taken()
  end

  defp effects_for(%{resource: %Skill{code: "culling_blade"}} = turn, _options) do
    if turn.defender.current_hp <= turn.defender.total_hp * (turn.resource.extra_multiplier + 0.01) do
      Effect.execute(turn)
    else
      turn
      |> Effect.atk_damage()
      |> Effect.base_damage()
    end
  end

  defp effects_for(%{resource: %Skill{code: "doom", debuff: nil}} = turn, _options) do
    turn
    |> Effect.add_debuff()
  end

  defp effects_for(%{resource: %Skill{code: "doom"}} = turn, _options) do
    turn
    |> Effect.silence()
    |> Effect.base_damage()
  end

  defp effects_for(%{resource: %Skill{code: "dream_coil"}, attacker: %{delayed_skill: nil}} = turn, _options) do
    turn
    |> Effect.add_delayed_skill()
  end

  defp effects_for(%{resource: %Skill{code: "dream_coil"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.stun()
  end

  defp effects_for(%{resource: %Skill{code: "elder_dragon_form", buff: nil}} = turn, _options) do
    turn
    |> Effect.add_buff()
  end

  defp effects_for(%{resource: %Skill{code: "elder_dragon_form"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.add_turn_power()
    |> Effect.hp_regen_by_base_amount()
  end

  defp effects_for(%{resource: %Skill{code: "gods_strength", buff: nil}} = turn, _options) do
    turn
    |> Effect.add_buff()
  end

  defp effects_for(%{resource: %Skill{code: "gods_strength"}} = turn, _options) do
    turn
    |> Effect.add_next_power_normal()
  end

  defp effects_for(%{resource: %Skill{code: "guardian_angel", buff: nil}} = turn, _options) do
    turn
    |> Effect.add_buff()
    |> Effect.atk_damage()
  end

  defp effects_for(%{resource: %Skill{code: "guardian_angel"}} = turn, _options) do
    turn
    |> Effect.hp_regen_by_base_amount()
    |> Effect.physical_invulnerability()
  end

  defp effects_for(%{resource: %Skill{code: "laguna_blade"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.null_armor()
  end

  defp effects_for(%{resource: %Skill{code: "life_drain"}, attacker: %{double_skill: nil}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.add_double_skill()
    |> Effect.hp_regen_by_total_mp()
    |> Effect.hp_regen_by_base_amount()
    |> Effect.physical_invulnerability()
  end

  defp effects_for(%{resource: %Skill{code: "life_drain"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.hp_regen_by_total_mp()
    |> Effect.hp_regen_by_base_amount()
    |> Effect.remove_double_skill()
    |> Effect.physical_invulnerability()
  end

  defp effects_for(%{resource: %Skill{code: "omnislash"}} = turn, _options) do
    turn
    |> roll(
      fn turn -> turn |> Effect.attacker_extra() |> Effect.base_damage() |> Effect.other_atk_damage() end,
      fn turn -> turn |> Effect.base_damage() |> Effect.random_atk_damage() end
    )
  end

  defp effects_for(
         %{resource: %Skill{code: "psionic_trap", debuff: nil}, attacker: %{permanent_skill: nil}} = turn,
         _options
       ) do
    turn
    |> Effect.add_permanent_skill()
  end

  defp effects_for(%{resource: %Skill{code: "psionic_trap", debuff: nil}} = turn, _options) do
    turn |> Effect.add_debuff() |> Effect.remove_permanent_skill()
  end

  defp effects_for(%{resource: %Skill{code: "psionic_trap"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.pierce_turn_armor()
    |> Effect.remove_turn_atk_by_multiplier()
  end

  defp effects_for(%{resource: %Skill{code: "rearm"} = resource} = turn, _options) do
    turn = Effect.reset_cooldowns(turn)
    last_skill = turn.attacker.last_skill

    if last_skill && last_skill.code != "rearm" && turn.attacker.current_mp >= last_skill.mp_cost do
      turn = Processor.cast_skill(turn, last_skill)

      %{turn | resource: resource, skill: resource}
      |> Effect.attacker_bonus(last_skill.name)
    else
      Effect.atk_damage(turn)
    end
  end

  defp effects_for(%{resource: %Skill{code: "remote_mines"}, attacker: %{delayed_skill: nil}} = turn, _options) do
    turn
    |> Effect.add_delayed_skill()
  end

  defp effects_for(%{resource: %Skill{code: "remote_mines"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.total_mp_damage()
  end

  defp effects_for(%{resource: %Skill{code: "spell_steal"} = resource} = turn, _options) do
    skill = turn.defender.last_skill

    if skill && skill != turn.resource do
      turn =
        turn
        |> Effect.add_turn_power()
        |> Effect.add_next_power()
        |> Processor.cast_skill(skill)

      %{turn | resource: resource, skill: resource}
      |> Effect.attacker_bonus(skill.name)
    else
      Effect.atk_damage(turn)
    end
  end

  defp effects_for(%{resource: %Skill{code: "time_lapse"}} = turn, _options) do
    turn
    |> Effect.reset_hp_to_last_turn()
    |> Effect.damage_by_last_damage_caused()
  end

  defp effects_for(%{resource: %Skill{code: "walrus_punch"}} = turn, _options) do
    turn
    |> Effect.base_damage()
    |> Effect.atk_damage()
    |> Effect.stun()
  end

  # PASSIVES

  defp effects_for(%{resource: %Skill{code: "counter_helix"}} = turn, %{is_attacking: false}) do
    turn
    |> roll(
      fn turn -> Effect.self_base_damage(turn) end,
      fn turn -> turn end
    )
  end

  defp effects_for(%{resource: %Skill{code: "feast"}} = turn, %{is_attacking: true}) do
    if Helper.normal_damage?(turn.defender) do
      turn
      |> Effect.hp_regen_by_base_amount()
      |> Effect.hp_regen_by_atk()
    else
      turn
    end
  end

  defp effects_for(%{resource: %Skill{code: "fiery_soul"}} = turn, %{is_attacking: true}) do
    if turn.skill && turn.skill.code != "basic_attack" do
      Effect.add_battle_power(turn)
    else
      turn
    end
  end

  defp effects_for(%{resource: %Skill{code: "fury_swipes"}} = turn, %{is_attacking: true}) do
    if Helper.normal_damage?(turn.defender) do
      turn
      |> Effect.refresh_debuff()
      |> Effect.add_debuff()
    else
      turn
    end
  end

  defp effects_for(%{resource: %Skill{code: "fury_swipes", debuff: true}} = turn, _options) do
    Effect.base_damage(turn)
  end

  defp effects_for(%{resource: %Skill{code: "jinada"}} = turn, %{is_attacking: true}) do
    if Helper.normal_damage?(turn.defender) do
      turn
      |> Effect.add_turn_power()
      |> Effect.base_damage()
    else
      turn
    end
  end

  defp effects_for(%{resource: %Skill{code: "phase_shift"}} = turn, %{is_attacking: false}) do
    turn
    |> roll(
      fn turn ->
        turn |> Effect.defender_invulnerability() |> Effect.defender_mp_cost() |> Effect.add_defender_cooldown()
      end,
      fn turn -> turn end
    )
  end

  # ULTIMATES

  defp effects_for(%{resource: %Skill{code: "battle_trance"}} = turn, %{is_attacking: false}) do
    result = turn.defender.current_hp - Helper.calculate_final_defender_damage(turn.attacker, turn.defender)

    if result / turn.defender.total_hp * 100 <= turn.resource.base_amount do
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

  defp effects_for(%{resource: %Skill{code: "battle_trance"}} = turn, %{is_attacking: true}) do
    result = turn.attacker.current_hp - turn.attacker.damage

    if result / turn.attacker.total_hp * 100 <= turn.resource.base_amount do
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

  defp effects_for(%{resource: %Skill{code: "coup"}} = turn, %{is_attacking: true}) do
    turn
    |> roll(
      fn turn -> turn |> Effect.add_turn_power() end,
      fn turn -> turn end
    )
  end

  # BASIC

  defp effects_for(%{resource: %Item{code: "ring_of_tarrasque"}} = turn, %{is_attacking: true}) do
    turn
    |> Effect.hp_regen_by_base_amount()
  end

  defp effects_for(%{resource: %Item{code: "sages_mask"}} = turn, %{is_attacking: true}) do
    turn
    |> Effect.mp_regen_by_base_amount()
  end

  defp effects_for(%{resource: %Item{code: "magic_stick"}} = turn, _options) do
    turn
    |> Effect.hp_regen_by_base_amount()
    |> Effect.mp_regen_by_extra_amount()
  end

  # RARE

  defp effects_for(%{resource: %Item{code: "shadow_blade"}, number: 1} = turn, %{is_attacking: true}) do
    turn
    |> Effect.base_amount_damage()
  end

  defp effects_for(%{resource: %Item{code: "vanguard"}} = turn, %{is_attacking: false}) do
    turn
    |> roll(
      fn turn -> turn |> Effect.block_damage() end,
      fn turn -> turn end
    )
  end

  defp effects_for(%{resource: %Item{code: "pipe_of_insight"}} = turn, _options) do
    turn
    |> Effect.add_next_armor()
  end

  defp effects_for(%{resource: %Item{code: "tranquil_boots"}} = turn, _options) do
    turn
    |> Effect.hp_regen_by_base_amount()
  end

  defp effects_for(%{resource: %Item{code: "arcane_boots"}} = turn, _options) do
    turn
    |> Effect.mp_regen_by_base_amount()
  end

  defp effects_for(%{resource: %Item{code: "maelstrom"}} = turn, %{is_attacking: true}) do
    turn
    |> roll(
      fn turn -> turn |> Effect.base_amount_damage() end,
      fn turn -> turn end
    )
  end

  # EPIC

  defp effects_for(%{resource: %Item{code: "assault_cuirass"}} = turn, %{is_attacking: true}) do
    turn
    |> Effect.pierce_turn_armor()
  end

  defp effects_for(%{resource: %Item{code: "diffusal_blade"}} = turn, %{is_attacking: true}) do
    turn
    |> Effect.mp_burn_by_defender_total_mp()
    |> Effect.damage_by_defender_total_mp()
  end

  defp effects_for(%{resource: %Item{code: code}} = turn, _options) when code in ["dagon", "dagon5"] do
    turn
    |> Effect.base_amount_damage()
    |> Effect.damage_type(Moba.damage_types().magic)
  end

  defp effects_for(%{resource: %Item{code: "heavens_halberd"}} = turn, _options) do
    turn
    |> Effect.disarm()
  end

  defp effects_for(%{resource: %Item{code: "bkb", defender_buff: nil}} = turn, _options) do
    turn
    |> Effect.attacker_extra()
    |> Effect.add_defender_buff()
  end

  defp effects_for(%{resource: %Item{code: "bkb"}} = turn, _options) do
    turn
    |> Effect.inneffectability()
  end

  # LEGENDARY

  defp effects_for(%{resource: %Item{code: "silver_edge"}, number: 1} = turn, %{is_attacking: true}) do
    turn
    |> Effect.base_amount_damage()
  end

  defp effects_for(%{resource: %Item{code: "silver_edge", attacker_debuff: nil}} = turn, %{active: true}) do
    turn
    |> Effect.attacker_extra()
    |> Effect.add_attacker_debuff()
    |> effects_for(%{is_attacking: true})
  end

  defp effects_for(%{resource: %Item{code: "silver_edge", attacker_debuff: true}} = turn, _options) do
    turn
    |> Effect.cut_hp_regen()
  end

  defp effects_for(%{resource: %Item{code: "daedalus"}} = turn, %{is_attacking: true}) do
    turn
    |> roll(
      fn turn -> turn |> Effect.add_turn_power() end,
      fn turn -> turn end
    )
  end

  defp effects_for(%{resource: %Item{code: "scythe_of_vyse"}} = turn, _options) do
    turn
    |> Effect.stun()
  end

  defp effects_for(%{resource: %Item{code: "satanic", final: true}} = turn, _options) do
    turn
    |> Effect.damage_regen()
  end

  defp effects_for(%{resource: %Item{code: "satanic"}} = turn, _options) do
    turn
    |> Effect.add_to_final()
  end

  defp effects_for(%{resource: %Item{code: "shivas_guard"}} = turn, _options) do
    turn
    |> Effect.add_next_armor()
    |> Effect.base_amount_damage()
  end

  defp effects_for(%{resource: %Item{code: "orchid_malevolence"}} = turn, _options) do
    turn
    |> Effect.pierce_turn_armor()
    |> Effect.silence()
  end

  defp effects_for(%{resource: %Item{code: "linkens_sphere"}} = turn, %{is_attacking: false}) do
    if Helper.disabled?(turn.defender) do
      turn
      |> Effect.inneffectability()
      |> Effect.add_defender_cooldown()
      |> Effect.mp_cost()
    else
      turn
    end
  end

  defp effects_for(turn, _options) do
    turn
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
