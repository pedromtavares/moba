defmodule Moba.Engine.HeroExpansionTest do
  use ExUnit.Case, async: true

  alias Moba.Engine.Core.{Buff, Effect, Helper, Logger, Processor, Turns}
  alias Moba.Engine.Schema.{Battler, Turn}
  alias Moba.Game.Schema.{Item, Skill}

  defp battler(attrs \\ %{}) do
    struct(
      Battler,
      Map.merge(
        %{
          name: "Hero",
          total_hp: 1000,
          current_hp: 500,
          total_mp: 100,
          current_mp: 50,
          base_atk: 20,
          atk: 20,
          base_power: 0,
          power: 0,
          base_armor: 0,
          armor: 0,
          speed: 0
        },
        attrs
      )
    )
  end

  defp skill(code, attrs \\ %{}) do
    struct(Skill, Map.merge(%{code: code, name: code, mp_cost: 0, cooldown: 6, damage_type: "magic", level: 1}, attrs))
  end

  defp item(code, attrs \\ %{}) do
    struct(Item, Map.merge(%{code: code, name: code, active: true, mp_cost: 0, cooldown: 5}, attrs))
  end

  defp fight(attacker, defender, skill \\ nil, item \\ nil) do
    attacker = %{
      attacker
      | active_skills: Enum.uniq([skill | attacker.active_skills]) |> Enum.reject(&is_nil/1),
        active_items: Enum.uniq([item | attacker.active_items]) |> Enum.reject(&is_nil/1)
    }

    Processor.process_turn(%Turn{
      number: 1,
      attacker: attacker,
      defender: defender,
      orders: %{skill: skill, item: item, auto: false}
    })
  end

  test "Sunder transfers each rank's HP, limited by the opponent's remaining HP" do
    for amount <- [100, 150, 200] do
      result = fight(battler(), battler(%{current_hp: 500}), skill("sunder", %{base_amount: amount}))
      assert result.attacker.current_hp == 500 + amount
      assert result.defender.current_hp == 500 - amount
      depleted = fight(battler(), battler(%{current_hp: 75}), skill("sunder", %{base_amount: amount}))
      assert depleted.attacker.current_hp == 575
      assert depleted.defender.current_hp == 0
    end
  end

  test "Sunder scales once with applicable Power and bypasses damage defenses at every rank" do
    for amount <- [100, 150, 200], {power, multiplier} <- [{0, 1.0}, {12, 1.6}, {20, 2.0}] do
      caster =
        battler(%{
          base_power: power,
          battle_power: power,
          turn_power: power,
          battle_power_magic: power,
          turn_power_magic: power,
          battle_power_normal: power,
          turn_power_normal: power
        })

      target = battler(%{base_armor: 90, invulnerable: true})
      result = fight(caster, target, skill("sunder", %{base_amount: amount}))
      transferred = round(amount * multiplier)
      assert result.attacker.current_hp == 500 + transferred
      assert result.defender.current_hp == 500 - transferred

      depleted = fight(caster, %{target | current_hp: 75}, skill("sunder", %{base_amount: amount}))
      assert depleted.attacker.current_hp == 575
      assert depleted.defender.current_hp == 0
    end
  end

  test "Mana Void deals fixed damage and restores full Energy while draining only what is available at every rank" do
    for {damage, energy} <- [{80, 20}, {120, 30}, {160, 40}], pool <- [0, 15, 100] do
      mana_void = skill("mana_void", %{base_damage: damage, base_amount: energy, mp_cost: energy, cooldown: 5})
      result = fight(battler(%{current_mp: energy}), battler(%{current_mp: pool}), mana_void)
      natural_regen = round(Float.ceil(100 * Moba.turn_mp_regen_multiplier()))
      drained = min(pool, energy)

      assert result.skill.code == "mana_void"
      assert result.defender.current_hp == 500 - damage
      assert result.defender.current_mp == pool - drained
      assert result.defender.mp_burn == drained
      assert result.attacker.current_mp == energy + natural_regen
      assert result.attacker.mp_regen == energy + natural_regen
      assert result.attacker.cooldowns["mana_void"] == 4
      description = Map.new(Logger.descriptions_for(result))["mana_void"]
      assert description =~ "#{damage} magic damage"
      assert description =~ "restored [mp]#{energy + natural_regen} Energy"
      assert description =~ "drained [mp]#{drained} Energy"
    end
  end

  test "Mana Void requires the initial Energy even though it refunds the cost" do
    for energy <- [20, 30, 40] do
      mana_void = skill("mana_void", %{base_damage: 80, base_amount: energy, mp_cost: energy})
      hero = battler(%{current_mp: energy - 1, active_skills: [mana_void]})
      refute Helper.can_use?(hero, mana_void, :active)
      result = fight(hero, battler(), mana_void)
      assert result.skill.code == "basic_attack"
      refute Map.has_key?(result.attacker.cooldowns, "mana_void")
      assert Helper.can_use?(%{hero | current_mp: energy}, mana_void, :active)
    end
  end

  test "Mana Void drains full Energy even when the caster's pool cannot fit all restoration" do
    mana_void = skill("mana_void", %{base_damage: 160, base_amount: 40, mp_cost: 40})
    result = fight(battler(%{base_power: 100, current_mp: 100}), battler(%{current_mp: 100}), mana_void)
    assert result.attacker.current_mp == 100
    assert result.defender.current_hp == 180
    assert result.defender.current_mp == 20
    assert result.defender.mp_burn == 80
  end

  test "Mana Void still refunds its cost and deals full damage against a zero-capacity target at every rank" do
    for {damage, energy} <- [{80, 20}, {120, 30}, {160, 40}] do
      mana_void = skill("mana_void", %{base_damage: damage, base_amount: energy, mp_cost: energy})
      result = fight(battler(%{current_mp: energy}), battler(%{current_mp: 0, total_mp: 0}), mana_void)
      assert result.defender.current_hp == 500 - damage
      assert result.defender.current_mp == 0
      assert result.attacker.current_mp == energy + round(Float.ceil(100 * Moba.turn_mp_regen_multiplier()))
    end
  end

  test "Mana Void applies general and magic Power once to damage, restoration and drain at every rank" do
    for {damage, energy} <- [{80, 20}, {120, 30}, {160, 40}] do
      mana_void = skill("mana_void", %{base_damage: damage, base_amount: energy, mp_cost: energy})
      attacker = battler(%{base_power: 20, battle_power_magic: 30, turn_power_magic: 10})
      defender = battler(%{current_mp: 40, base_armor: 25})
      result = fight(attacker, defender, mana_void)
      restored = round(energy * 1.6)
      natural_regen = round(Float.ceil(100 * Moba.turn_mp_regen_multiplier()) * 1.6)

      assert result.defender.current_hp == 500 - round(damage * 1.6 * 0.75)
      assert result.defender.current_mp == max(40 - restored, 0)
      assert result.attacker.mp_regen == restored + natural_regen
      assert result.attacker.current_mp == min(50 - energy + restored + natural_regen, 100)

      immune = fight(attacker, %{defender | invulnerable: true}, mana_void)
      assert immune.defender.current_hp == 500
      assert immune.defender.current_mp == result.defender.current_mp
      assert immune.attacker.current_mp == result.attacker.current_mp
    end
  end

  test "Mana Void limits drain using Energy remaining after other burns and restoration" do
    mana_void = skill("mana_void", %{base_damage: 80, base_amount: 20, mp_cost: 20})

    for regen <- [0, 5] do
      result = fight(battler(), battler(%{current_mp: 30, mp_burn: 20, mp_regen: regen}), mana_void)
      assert result.defender.current_hp == 420
      assert result.defender.current_mp == 0
      assert result.defender.mp_burn == 30 + regen
      assert result.attacker.mp_regen == 20 + round(Float.ceil(100 * Moba.turn_mp_regen_multiplier()))
    end
  end

  test "Chakra and Octarine stack on skill, ultimate, and item cooldowns" do
    cooldowns = %{"normal" => 6, "ultimate" => 6, "item" => 6, "ready" => -1}
    hero = battler(%{cooldowns: cooldowns, future_cooldowns: cooldowns})
    chakra = skill("chakra_magic", %{base_amount: 30, extra_amount: 2})
    octarine = item("octarine_core", %{extra_amount: 2, cooldown: 6, mp_cost: 15})
    result = fight(hero, battler(), chakra, octarine)
    for code <- ["normal", "ultimate", "item"], do: assert(result.attacker.cooldowns[code] == 1)
    assert result.attacker.cooldowns["chakra_magic"] == 3
    assert result.attacker.cooldowns["octarine_core"] == 5
    assert result.attacker.cooldowns["ready"] < 0
    assert result.attacker.future_cooldowns == result.attacker.cooldowns
  end

  test "Rearm can repeat Chakra and reset all earlier cooldowns" do
    chakra = skill("chakra_magic", %{base_amount: 10, extra_amount: 1})
    rearm = skill("rearm", %{power_amount: 0, mp_cost: 20})
    hero = battler(%{current_mp: 100, last_skill: chakra, cooldowns: %{"item" => 5}, future_cooldowns: %{"item" => 5}})
    result = fight(hero, battler(), rearm)
    refute Map.has_key?(result.attacker.cooldowns, "item")
    assert result.attacker.mp_regen > 10
  end

  test "Chakra cleanses one debuff per rank, newest first across both debuff types" do
    applied =
      Enum.reduce(1..6, %Turn{attacker: battler(), defender: battler()}, fn i, turn ->
        turn = %{turn | resource: skill("debuff_#{i}", %{duration: 3})}
        if rem(i, 2) == 1, do: Effect.add_debuff(turn), else: Effect.add_attacker_debuff(turn)
      end)

    for rank <- 1..5 do
      chakra = skill("chakra_magic", %{level: rank, base_amount: 5 + 5 * rank, extra_amount: 1})
      hero = %{applied.defender | current_mp: 0, debuffs: applied.defender.debuffs ++ [%Buff{duration: 0}]}
      result = fight(hero, battler(), chakra)
      remaining = result.attacker.debuffs ++ result.attacker.attacker_debuffs
      assert MapSet.new(remaining, & &1.resource.code) == MapSet.new(1..(6 - rank), &"debuff_#{&1}")
      assert result.attacker.mp_regen == chakra.base_amount + Float.ceil(100 * Moba.turn_mp_regen_multiplier())
      assert Map.new(Logger.descriptions_for(result))["chakra_magic"] =~ "removed [status]#{rank} "
    end
  end

  test "Chakra rank one clears the newest healing counter, rank two clears both, preserving healing buffs" do
    bloodstone = item("bloodstone", %{duration: 2, hp_regen_multiplier: 0.4})
    silver_edge = item("silver_edge", %{duration: 2, hp_regen_multiplier: 0.5})
    flames = skill("purifying_flames", %{base_amount: 100, duration: 3})

    for {first, second, rank_one_healing, rank_one_stolen} <- [
          {silver_edge, bloodstone, 50, 0},
          {bloodstone, silver_edge, 60, 40}
        ] do
      applied =
        %Turn{attacker: battler(), defender: battler(), resource: first}
        |> Effect.add_attacker_debuff()
        |> Map.put(:resource, second)
        |> Effect.add_attacker_debuff()

      victim = %{applied.defender | buffs: [%Buff{resource: flames, duration: 3}]}

      for {rank, healing, stolen} <- [{1, rank_one_healing, rank_one_stolen}, {2, 100, 0}] do
        result = fight(victim, battler(), skill("chakra_magic", %{level: rank, base_amount: 10, extra_amount: 1}))
        assert result.attacker.hp_regen == healing
        assert result.defender.hp_regen == stolen
        assert [%Buff{resource: %{code: "purifying_flames"}, duration: 2}] = result.attacker.buffs
        assert length(result.attacker.attacker_debuffs) == 2 - rank
      end
    end
  end

  test "Chakra does not count expired effects or prevent fresh debuffs after cleansing" do
    silver_edge = item("silver_edge", %{duration: 2, hp_regen_multiplier: 0.5})
    hero = battler(%{attacker_debuffs: [%Buff{resource: silver_edge, duration: 0}]})
    result = fight(hero, battler(), skill("chakra_magic", %{level: 5, base_amount: 30, extra_amount: 2}))
    assert result.attacker.attacker_debuffs == []
    assert Map.new(Logger.descriptions_for(result))["chakra_magic"] =~ "removed [status]0 debuffs[/status]"
    applied = fight(battler(), result.attacker, nil, silver_edge)
    assert [%Buff{resource: %{code: "silver_edge"}, duration: 2}] = applied.defender.attacker_debuffs
  end

  test "one Chakra removal clears a stacked debuff as a single effect" do
    swipes = skill("fury_swipes", %{duration: 3, base_damage: 5})
    silver_edge = item("silver_edge", %{duration: 2, hp_regen_multiplier: 0.5})

    applied =
      %Turn{attacker: battler(), defender: battler(), resource: silver_edge}
      |> Effect.add_attacker_debuff()
      |> Map.put(:resource, swipes)
      |> Effect.add_debuff()
      |> Effect.add_debuff()
      |> Effect.add_debuff()

    result = fight(applied.defender, battler(), skill("chakra_magic", %{level: 1, base_amount: 10, extra_amount: 1}))
    assert result.attacker.debuffs == []
    assert [%Buff{resource: %{code: "silver_edge"}}] = result.attacker.attacker_debuffs
    assert Map.new(Logger.descriptions_for(result))["chakra_magic"] =~ "removed [status]1 debuff[/status]"
  end

  test "debuff application order survives ticking, JSON serialization and reloading" do
    silver_edge = item("silver_edge", %{duration: 3, hp_regen_multiplier: 0.5})
    bloodstone = item("bloodstone", %{duration: 3, hp_regen_multiplier: 0.4})
    older = skill("older_debuff", %{duration: 3})

    applied =
      %Turn{attacker: battler(), defender: battler(), resource: silver_edge}
      |> Effect.add_attacker_debuff()
      |> Map.put(:resource, older)
      |> Effect.add_debuff()
      |> Map.put(:resource, bloodstone)
      |> Effect.add_attacker_debuff()

    ticked = fight(applied.defender, battler())
    serialized = Turns.serialize(ticked)
    dumped = Ecto.embedded_dump(serialized.attacker, :json) |> Jason.encode!() |> Jason.decode!()
    loaded = Ecto.embedded_load(Battler, dumped, :json)
    resources = Map.new([silver_edge, older, bloodstone], &{&1.code, &1})

    hero =
      Enum.reduce([:debuffs, :attacker_debuffs], loaded, fn key, hero ->
        buffs =
          Enum.map(Map.fetch!(hero, key), fn buff ->
            buff = Turns.keys_to_atoms(buff)
            Map.put(buff, :resource, Map.fetch!(resources, buff.resource_code))
          end)

        Map.put(hero, key, buffs)
      end)

    cleansed = Effect.dispel_debuffs(%Turn{attacker: hero, defender: battler(), resource: skill("chakra_magic")}, 2)
    assert cleansed.attacker.debuffs == []
    assert [%{resource: %{code: "silver_edge"}}] = cleansed.attacker.attacker_debuffs
  end

  test "Pulse Nova activates immediately and costs Energy once" do
    nova = skill("pulse_nova", %{base_damage: 40, mp_cost: 6, cooldown: 0})
    result = fight(battler(), battler(), nova)
    assert result.defender.current_hp == 460
    assert result.attacker.pulse_nova.code == "pulse_nova"
    assert result.attacker.current_mp == 50 - 6 + Float.ceil(100 * Moba.turn_mp_regen_multiplier())
    serialized = Turns.serialize(result)
    assert serialized.attacker.pulse_nova_code == "pulse_nova"
    assert serialized.attacker.pulse_nova_level == 1
    dumped = Ecto.embedded_dump(serialized.attacker, :json)
    loaded = Ecto.embedded_load(Battler, dumped, :json)
    assert loaded.pulse_nova_code == "pulse_nova"
  end

  test "Nova remains magic alongside physical attacks, disarm, evasion, and physical immunity" do
    nova = skill("pulse_nova", %{base_damage: 40, mp_cost: 6})

    for attrs <- [%{evaded: true}, %{physically_invulnerable: true}] do
      result = fight(battler(%{pulse_nova: nova}), battler(Map.merge(%{base_armor: 50}, attrs)))
      assert result.defender.damage == 20
    end

    result = fight(battler(%{pulse_nova: nova, disarmed: true}), battler(%{base_armor: 50}))
    assert result.defender.damage == 20
    normal = fight(battler(%{pulse_nova: nova}), battler(%{base_armor: 50}))
    assert normal.defender.damage == 30
    assert normal.defender.last_damage_taken == 30
    immune = fight(battler(%{pulse_nova: nova}), battler(%{invulnerable: true}))
    assert immune.defender.damage == 0
  end

  test "Nova damage scales with magic Power even when the selected action is physical" do
    nova = skill("pulse_nova", %{base_damage: 40, mp_cost: 6})
    result = fight(battler(%{pulse_nova: nova, battle_power_magic: 50}), battler())
    assert result.defender.damage == 80
  end

  test "Nova cannot be selected or manually stopped while running, and a stale selection falls back to attacking" do
    nova = skill("pulse_nova", %{base_damage: 40, mp_cost: 6, cooldown: 0})
    hero = battler(%{pulse_nova: nova, current_mp: 50, active_skills: [nova]})
    refute Helper.can_use?(hero, nova, :active)
    result = fight(hero, battler(), nova)
    assert result.attacker.pulse_nova == nova
    assert result.skill.code == "basic_attack"
    assert result.defender.damage == 60
    assert result.attacker.current_mp == 50 - 6 + Float.ceil(100 * Moba.turn_mp_regen_multiplier())
  end

  test "Rearm cannot stop or duplicate an already running Nova" do
    nova = skill("pulse_nova", %{base_damage: 40, mp_cost: 6, cooldown: 0})
    rearm = skill("rearm", %{power_amount: 0, mp_cost: 20})
    hero = battler(%{pulse_nova: nova, current_mp: 100, last_skill: nova})
    result = fight(hero, battler(), rearm)
    assert result.attacker.pulse_nova == nova
    assert result.defender.damage == 40
    assert result.attacker.current_mp == 100 - 6 - 20 + Float.ceil(100 * Moba.turn_mp_regen_multiplier())
  end

  test "Nova ends when a pulse cannot be paid and can be activated again after restoring Energy" do
    nova = skill("pulse_nova", %{base_damage: 40, mp_cost: 6, cooldown: 0})
    result = fight(battler(%{pulse_nova: nova, current_mp: 5}), battler())
    assert is_nil(result.attacker.pulse_nova)
    assert result.defender.damage == 20
    assert Helper.can_use?(%{result.attacker | active_skills: [nova]}, nova, :active)
    restarted = fight(%{result.attacker | mp_regen: 0, damage: 0}, battler(), nova)
    assert restarted.attacker.pulse_nova == nova
    assert restarted.defender.damage == 40
  end

  test "AI keeps Nova running alongside other actions" do
    nova = skill("pulse_nova", %{base_damage: 40, mp_cost: 6, cooldown: 0})
    hero = battler(%{pulse_nova: nova, active_skills: [nova], skill_order: [nova]})
    auto = Processor.process_turn(%Turn{number: 1, attacker: hero, defender: battler(), orders: %{auto: true}})
    assert auto.attacker.pulse_nova
    assert auto.defender.damage == 60
  end

  test "Purifying Flames heals only on the target's following three turns" do
    flames = skill("purifying_flames", %{base_damage: 150, base_amount: 20, duration: 3})
    result = fight(battler(), battler(), flames)
    assert result.defender.current_hp == 350
    assert [%Buff{duration: 3}] = result.defender.buffs

    for duration <- [3, 2, 1, 0] do
      hero = battler(%{buffs: [%Buff{resource: flames, duration: duration}]})
      healed = fight(hero, battler())
      assert healed.attacker.current_hp == if(duration > 0, do: 520, else: 500)
    end
  end

  test "Fortune's End pauses healing, temporary defenses and Power while preserving buffs, base stats and debuffs" do
    flames = skill("purifying_flames", %{base_amount: 20})

    target =
      battler(%{
        base_armor: 10,
        next_armor: 80,
        invulnerable: true,
        battle_power: 25,
        buffs: [%Buff{resource: flames, duration: 3}],
        defender_buffs: [%Buff{resource: item("bkb"), duration: 2}],
        attacker_debuffs: [%Buff{resource: skill("rupture"), duration: 3}]
      })

    result = fight(battler(), target, skill("fortunes_end", %{base_damage: 40, duration: 2, cooldown: 5}))
    assert result.defender.damage == 36
    assert result.defender.buffs == target.buffs
    assert result.defender.defender_buffs == target.defender_buffs
    assert result.defender.paused_bonuses["battle_power"] == 25
    assert result.defender.battle_power == 0
    assert result.defender.base_armor == 10
    assert length(result.defender.attacker_debuffs) == 2
  end

  test "Rupture deals fixed magic damage at every rank before its reflection debuff" do
    for {rank, damage, reflected} <- [{1, 50, 0.4}, {2, 75, 0.5}, {3, 100, 0.6}] do
      rupture = skill("rupture", %{level: rank, base_damage: damage, extra_multiplier: reflected, duration: 3})
      applied = fight(battler(), battler(), rupture)
      assert applied.defender.current_hp == 500 - damage
      assert [%Buff{resource: %{code: "rupture"}, duration: 3}] = applied.defender.attacker_debuffs
      description = Map.new(Logger.descriptions_for(applied))["rupture"]
      assert description =~ "#{damage} magic damage"
      assert description =~ "three turns"

      result = fight(%{applied.defender | damage: 0, effects: []}, battler())
      assert result.defender.damage == 20
      assert result.attacker.damage == round(20 * reflected)
    end
  end

  test "Rupture's initial damage respects Power, Armor and invulnerability, and cleansing cannot undo it" do
    rupture = skill("rupture", %{base_damage: 50, extra_multiplier: 0.5, duration: 3})
    result = fight(battler(%{base_power: 20}), battler(%{base_armor: 25}), rupture)
    assert result.defender.current_hp == 455
    immune = fight(battler(%{base_power: 20}), battler(%{invulnerable: true}), rupture)
    assert immune.defender.current_hp == 500

    chakra = skill("chakra_magic", %{base_amount: 10, extra_amount: 1})
    cleansed = fight(%{result.defender | damage: 0, effects: []}, battler(), chakra)
    assert cleansed.attacker.current_hp == 455
    assert cleansed.attacker.attacker_debuffs == []
  end

  test "casting Rupture while ruptured logs the initial hit and one reflected hit separately" do
    rupture = skill("rupture", %{base_damage: 50, extra_multiplier: 0.5, duration: 3})
    hero = battler(%{name: "Bloodseeker A", attacker_debuffs: [%Buff{resource: rupture, duration: 3}]})
    result = fight(hero, battler(%{name: "Bloodseeker B"}), rupture)
    assert result.defender.current_hp == 450
    assert result.attacker.current_hp == 475
    description = Map.new(Logger.descriptions_for(result))["rupture"]
    assert description =~ "50 magic damage"
    assert description =~ "25 reflected damage"
  end

  test "Rupture reflects mitigated damage once without recursively reflecting" do
    rupture = skill("rupture", %{extra_multiplier: 0.5, duration: 3})

    attacker =
      battler(%{
        base_atk: 100,
        base_armor: 90,
        attacker_debuffs: [%Buff{resource: rupture, duration: 3}]
      })

    target = battler(%{base_armor: 50, attacker_debuffs: [%Buff{resource: rupture, duration: 3}]})
    result = fight(attacker, target)
    assert result.defender.damage == 50
    assert result.attacker.damage == 25
    assert result.attacker.current_hp == 475
    immune = fight(attacker, %{target | invulnerable: true})
    assert immune.attacker.damage == 0
  end

  test "reflection runs after Nova damage too" do
    nova = skill("pulse_nova", %{base_damage: 40, mp_cost: 6})
    rupture = skill("rupture", %{extra_multiplier: 0.5, duration: 3})
    result = fight(battler(%{pulse_nova: nova, attacker_debuffs: [%Buff{resource: rupture, duration: 3}]}), battler())
    assert result.defender.damage == 60
    assert result.attacker.damage == 30
  end

  test "Rupture lasts three enemy turns" do
    rupture = skill("rupture", %{extra_multiplier: 0.5, duration: 3})
    applied = fight(battler(), battler(), rupture)
    assert [%Buff{duration: 3}] = applied.defender.attacker_debuffs

    for duration <- [3, 2, 1, 0] do
      result = fight(battler(%{attacker_debuffs: [%Buff{resource: rupture, duration: duration}]}), battler())
      assert result.attacker.damage == if(duration > 0, do: 10, else: 0)
      if duration > 0, do: assert(hd(result.attacker.attacker_debuffs).duration == duration - 1)
    end
  end

  test "Bloodstone costs Energy, preserves HP and has no passive lifesteal" do
    bloodstone = item("bloodstone", %{hp_regen_multiplier: 0.4, duration: 2, mp_cost: 10, cooldown: 6})
    hero = battler(%{active_items: [bloodstone], base_atk: 100})
    idle = fight(hero, battler())
    assert idle.attacker.hp_regen == 0
    assert idle.attacker.defender_buffs == []
    result = fight(hero, battler(), nil, bloodstone)
    assert result.attacker.current_hp == 500
    assert result.attacker.current_mp == 40 + Float.ceil(100 * Moba.turn_mp_regen_multiplier())
    assert result.attacker.cooldowns["bloodstone"] == 5
    assert result.attacker.defender_buffs == []
    assert [%Buff{resource: %{code: "bloodstone"}, duration: 2}] = result.defender.attacker_debuffs
    assert Map.new(Logger.descriptions_for(result))["bloodstone"] =~ "affected by"

    serialized = Turns.serialize(result)
    dumped = Ecto.embedded_dump(serialized.defender, :json)
    loaded = Ecto.embedded_load(Battler, dumped, :json)
    assert [%Buff{resource_code: "bloodstone", duration: 2}] = loaded.attacker_debuffs
  end

  test "Bloodstone steals resolved healing for exactly two enemy turns without amplifying it again" do
    bloodstone = item("bloodstone", %{hp_regen_multiplier: 0.4, duration: 2})
    pulse = skill("death_pulse", %{base_damage: 0, base_amount: 100})

    for {duration, stolen} <- [{2, 48}, {1, 48}, {0, 0}] do
      owner = battler(%{name: "Thief", base_power: 100})

      victim =
        battler(%{name: "Healer", base_power: 20, attacker_debuffs: [%Buff{resource: bloodstone, duration: duration}]})

      result = fight(victim, owner, pulse)
      assert result.attacker.hp_regen == 120 - stolen
      assert result.defender.hp_regen == stolen
      assert result.attacker.current_hp == 620 - stolen
      assert result.defender.current_hp == 500 + stolen

      if duration > 0 do
        assert hd(result.attacker.attacker_debuffs).duration == duration - 1
        assert Map.new(Logger.descriptions_for(result))["bloodstone"] =~ "stole"
      end
    end
  end

  test "Bloodstone steals late Sunder and Satanic healing and leaves Guardian Angel effective" do
    bloodstone = item("bloodstone", %{hp_regen_multiplier: 0.4, duration: 2})
    owner = battler()
    victim = battler(%{attacker_debuffs: [%Buff{resource: bloodstone, duration: 2}]})
    sunder = fight(victim, owner, skill("sunder", %{base_amount: 100}))
    assert sunder.attacker.hp_regen == 60
    assert sunder.defender.hp_regen == 40
    satanic = fight(%{victim | base_atk: 100}, owner, nil, item("satanic", %{hp_regen_multiplier: 1.0}))
    assert satanic.attacker.hp_regen == 60
    assert satanic.defender.hp_regen == 40
    assert Map.new(Logger.descriptions_for(satanic))["bloodstone"] =~ "stole [hp]40 Health"

    angel = skill("guardian_angel", %{base_amount: 270, duration: 2, armor_amount: 200, atk_multiplier: 1})
    omni = fight(%{victim | base_power: 26}, owner, angel)
    assert omni.attacker.hp_regen == 204
    assert omni.defender.hp_regen == 136
    assert omni.attacker.next_armor == 200
  end

  test "Bloodstone uses actual healing after HP limits and Silver Edge reduction" do
    bloodstone = item("bloodstone", %{hp_regen_multiplier: 0.4, duration: 2})
    owner = battler()
    victim = battler(%{attacker_debuffs: [%Buff{resource: bloodstone, duration: 2}]})
    pulse = skill("death_pulse", %{base_damage: 0, base_amount: 100})
    full = fight(%{victim | current_hp: 1000}, owner, pulse)
    assert full.defender.hp_regen == 0
    capped = fight(%{victim | current_hp: 995}, owner, pulse)
    assert capped.attacker.current_hp == 998
    assert capped.defender.hp_regen == 2
    silver_edge = item("silver_edge", %{hp_regen_multiplier: 0.5})
    victim = %{victim | attacker_debuffs: victim.attacker_debuffs ++ [%Buff{resource: silver_edge, duration: 1}]}
    reduced = fight(victim, owner, pulse)
    assert reduced.attacker.hp_regen == 30
    assert reduced.defender.hp_regen == 20
  end

  test "Silver Edge reduces every rank of Sunder's late healing for exactly its remaining turns" do
    silver_edge = item("silver_edge", %{hp_regen_multiplier: 0.5, duration: 2})

    for amount <- [100, 150, 200], duration <- [2, 1, 0] do
      victim = battler(%{base_power: 100, attacker_debuffs: [%Buff{resource: silver_edge, duration: duration}]})
      result = fight(victim, battler(), skill("sunder", %{base_amount: amount}))
      transferred = amount * 2
      restored = if duration > 0, do: div(transferred, 2), else: transferred
      assert result.attacker.current_hp == 500 + restored
      assert result.defender.current_hp == 500 - transferred

      if duration > 0 do
        assert hd(result.attacker.attacker_debuffs).duration == duration - 1
        assert Map.new(Logger.descriptions_for(result))["silver_edge"] =~ "#{div(transferred, 2)}"
      end
    end
  end

  test "Silver Edge reduces combined early and late healing once" do
    silver_edge = item("silver_edge", %{hp_regen_multiplier: 0.5, duration: 2})
    victim = battler(%{attacker_debuffs: [%Buff{resource: silver_edge, duration: 2}]})
    pulse = skill("death_pulse", %{base_damage: 100, base_amount: 100})
    satanic = item("satanic", %{hp_regen_multiplier: 1.0})
    result = fight(victim, battler(), pulse, satanic)
    assert result.attacker.current_hp == 600
    assert result.attacker.hp_regen == 100
    assert result.defender.current_hp == 400
    assert Map.new(Logger.descriptions_for(result))["silver_edge"] =~ "100"
  end

  test "Silver Edge reduces healing before Bloodstone steals, regardless of application order" do
    silver_edge = item("silver_edge", %{hp_regen_multiplier: 0.5, duration: 2})
    bloodstone = item("bloodstone", %{hp_regen_multiplier: 0.4, duration: 2})

    for amount <- [100, 150, 200], order <- [[silver_edge, bloodstone], [bloodstone, silver_edge]] do
      statuses = Enum.map(order, &%Buff{resource: &1, duration: 2})
      victim = battler(%{base_power: 100, attacker_debuffs: statuses})
      result = fight(victim, battler(), skill("sunder", %{base_amount: amount}))
      transferred = amount * 2
      reduced = div(transferred, 2)
      stolen = round(reduced * 0.4)
      assert result.attacker.current_hp == 500 + reduced - stolen
      assert result.defender.current_hp == 500 - transferred + stolen
      assert Map.new(Logger.descriptions_for(result))["bloodstone"] =~ "#{stolen} Health"
    end
  end

  test "stacked Silver Edge effects multiply and a cleanse cancels the reduction before healing settles" do
    silver_edge = item("silver_edge", %{hp_regen_multiplier: 0.5, duration: 2})
    statuses = List.duplicate(%Buff{resource: silver_edge, duration: 2}, 2)
    result = fight(battler(%{attacker_debuffs: statuses}), battler(), skill("sunder", %{base_amount: 100}))
    assert result.attacker.current_hp == 525
    assert result.defender.current_hp == 400

    flames = skill("purifying_flames", %{base_amount: 100, duration: 3})
    victim = battler(%{buffs: [%Buff{resource: flames, duration: 3}], attacker_debuffs: statuses})
    chakra = skill("chakra_magic", %{base_amount: 10, extra_amount: 1})
    cleansed = fight(victim, battler(), chakra)
    assert cleansed.attacker.current_hp == 600
    assert cleansed.attacker.attacker_debuffs == []
    refute Map.has_key?(Map.new(Logger.descriptions_for(cleansed)), "silver_edge")
  end

  test "self-cleansing removes Bloodstone and Silver Edge while preserving healing buffs" do
    bloodstone = item("bloodstone", %{hp_regen_multiplier: 0.4, duration: 2})
    silver_edge = item("silver_edge", %{hp_regen_multiplier: 0.5})
    flames = skill("purifying_flames", %{base_amount: 100, duration: 3})

    victim =
      battler(%{
        buffs: [%Buff{resource: flames, duration: 3}],
        debuffs: [%Buff{resource: skill("doom"), duration: 2}],
        attacker_debuffs: [%Buff{resource: bloodstone, duration: 2}, %Buff{resource: silver_edge, duration: 2}]
      })

    cleansed = Effect.dispel_debuffs(%Turn{attacker: victim, defender: battler(), resource: skill("chakra_magic")})
    assert cleansed.attacker.debuffs == []
    assert cleansed.attacker.attacker_debuffs == []
    assert cleansed.attacker.buffs == victim.buffs
    result = fight(cleansed.attacker, battler())
    assert result.attacker.hp_regen == 100
    assert result.defender.hp_regen == 0
  end

  test "pausing Bloodstone's caster does not cleanse the victim's debuff" do
    bloodstone = item("bloodstone", %{hp_regen_multiplier: 0.4, duration: 2})
    victim = battler(%{attacker_debuffs: [%Buff{resource: bloodstone, duration: 2}]})
    result = fight(victim, battler(), skill("fortunes_end", %{base_damage: 40, duration: 2, cooldown: 5}))
    assert [%Buff{resource: %{code: "bloodstone"}, duration: 1}] = result.attacker.attacker_debuffs
  end

  test "Soul Booster combines active and passive restoration, including while the active is cooling down" do
    booster = item("soul_booster", %{passive: true, base_amount: 25, extra_amount: 2})
    hero = battler(%{current_mp: 0, passive_items: [booster]})
    result = fight(hero, battler(), nil, booster)
    assert result.attacker.mp_regen == 27 + Float.ceil(100 * Moba.turn_mp_regen_multiplier())
    cooled = fight(%{hero | cooldowns: %{"soul_booster" => 3}, future_cooldowns: %{"soul_booster" => 3}}, battler())
    assert cooled.attacker.mp_regen == 2 + Float.ceil(100 * Moba.turn_mp_regen_multiplier())
    enemy_turn = fight(battler(), hero)
    assert enemy_turn.defender.mp_regen == 0
  end

  test "new combat effects have readable log descriptions" do
    skills = [
      skill("sunder", %{base_amount: 100}),
      skill("mana_void", %{base_damage: 80, base_amount: 20, mp_cost: 20}),
      skill("pulse_nova", %{base_damage: 40, mp_cost: 6}),
      skill("rupture", %{duration: 3, extra_multiplier: 0.5}),
      skill("chakra_magic", %{base_amount: 10, extra_amount: 1}),
      skill("purifying_flames", %{base_damage: 150, base_amount: 20, duration: 3}),
      skill("fortunes_end", %{base_damage: 40, duration: 2, cooldown: 5})
    ]

    items = [
      item("octarine_core", %{extra_amount: 2}),
      item("soul_booster", %{base_amount: 25})
    ]

    turns = Enum.map(skills, &fight(battler(), battler(), &1)) ++ Enum.map(items, &fight(battler(), battler(), nil, &1))

    for turn <- turns, {_code, description} <- Logger.descriptions_for(turn) do
      refute description =~ "Missing description"
    end
  end
end
