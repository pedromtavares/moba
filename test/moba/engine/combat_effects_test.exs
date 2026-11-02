defmodule Moba.Engine.CombatEffectsTest do
  use ExUnit.Case, async: true

  alias Test.CombatCase, as: Combat
  alias Moba.Engine.Core.Buff

  # All amounts use the rank-one dev catalog and a 100 Attack, zero Power hero.
  for {code, damage, healing} <- [
        {"lightning_bolt", 100, 0},
        {"mana_burn", 50, 0},
        {"mana_shield", 50, 0},
        {"death_pulse", 50, 50},
        {"decay", 130, 70},
        {"double_edge", 180, 0},
        {"blink_strike", 140, 0},
        {"shuriken_toss", 143, 0},
        {"static_link", 140, 0},
        {"maledict", 50, 0},
        {"walrus_punch", 125, 0},
        {"rupture", 50, 0},
        {"guardian_angel", 0, 70},
        {"gods_strength", 0, 0},
        {"borrowed_time", 0, 0},
        {"elder_dragon_form", 16, 27},
        {"empower", 134, 0},
        {"doom", 70, 0},
        {"fortunes_end", 40, 0},
        {"pulse_nova", 40, 0},
        {"purifying_flames", 150, 0},
        {"blade_fury", 140, 0},
        {"life_drain", 100, 220}
      ] do
    @code code
    @damage damage
    @healing healing
    test "#{code} has its intended immediate damage and healing" do
      skill = Combat.skill(@code)
      result = resolve([skill], [], skill)
      assert result.defender.damage == @damage
      assert result.attacker.hp_regen == @healing
      assert result.defender.current_hp == 800 - @damage
    end
  end

  test "Power and Armor each apply once to combined magic skill and item damage" do
    bolt = Combat.skill("lightning_bolt")
    dagon = Combat.item("dagon")

    result =
      resolve([bolt, dagon], [], bolt, dagon, fn turn ->
        %{turn | attacker: %{turn.attacker | base_power: 20}, defender: %{turn.defender | base_armor: 30}}
      end)

    assert result.defender.damage == 147
  end

  test "magic damage does not trigger evade or consume its cooldown" do
    bolt = Combat.skill("lightning_bolt")
    result = resolve([bolt], [], bolt, nil, &put_in(&1.defender.speed, 200))

    assert result.defender.damage == 100
    refute result.defender.evaded
    refute Map.has_key?(result.defender.future_cooldowns, "evade")
    refute Enum.any?(result.defender.effects, &(&1["resource"] == "evade"))
  end

  test "Illuminate's charging and release turns do not trigger evade" do
    illuminate = %{Combat.skill("illuminate") | base_damage: 380, level: 3}

    charging = resolve([illuminate], [], illuminate, nil, &put_in(&1.defender.speed, 200))
    assert charging.defender.damage == 0
    refute charging.defender.evaded
    refute Map.has_key?(charging.defender.future_cooldowns, "evade")

    released =
      resolve([illuminate], [], nil, nil, fn turn ->
        %{
          turn
          | attacker: %{
              turn.attacker
              | double_skill: illuminate,
                last_skill: illuminate,
                base_power: 33,
                battle_power: 16
            },
            defender: %{turn.defender | speed: 200, base_armor: 15, current_hp: 732}
        }
      end)

    assert released.defender.damage == 481
    assert released.defender.current_hp == 251
    refute released.defender.evaded
    refute Map.has_key?(released.defender.future_cooldowns, "evade")
    refute Enum.any?(released.defender.effects, &(&1["resource"] == "evade"))
  end

  test "evade still blocks non-ultimate physical skills and respects its cooldown" do
    shuriken = Combat.skill("shuriken_toss")
    evaded = resolve([shuriken], [], shuriken, nil, &put_in(&1.defender.speed, 200))

    assert evaded.defender.evaded
    assert evaded.defender.damage == 0
    assert evaded.defender.future_cooldowns["evade"] == 2

    cooling =
      resolve([shuriken], [], shuriken, nil, fn turn ->
        %{turn | defender: %{turn.defender | speed: 200, cooldowns: %{"evade" => 1}, future_cooldowns: %{"evade" => 1}}}
      end)

    refute cooling.defender.evaded
    assert cooling.defender.damage == 143
    assert cooling.defender.future_cooldowns["evade"] == 1
  end

  test "pure damage and physical ultimates never trigger evade" do
    pure_bolt = %{Combat.skill("lightning_bolt") | damage_type: "pure"}
    walrus = Combat.skill("walrus_punch")

    for skill <- [pure_bolt, walrus] do
      result = resolve([skill], [], skill, nil, &put_in(&1.defender.speed, 200))
      assert result.defender.damage > 0
      refute result.defender.evaded
      refute Map.has_key?(result.defender.future_cooldowns, "evade")
    end
  end

  test "evading a physical skill still allows separate Pulse Nova magic damage" do
    shuriken = Combat.skill("shuriken_toss")
    nova = Combat.skill("pulse_nova")

    result =
      resolve([shuriken, nova], [], shuriken, nil, fn turn ->
        %{turn | attacker: %{turn.attacker | pulse_nova: nova}, defender: %{turn.defender | speed: 200}}
      end)

    assert result.defender.evaded
    # Shuriken's -10 Armor still applies, increasing Nova's 40 magic damage to 44.
    assert result.defender.damage == 44
    assert result.defender.current_hp == 756
  end

  test "Coup and Daedalus armor penetration stack additively into negative Armor" do
    coup = Combat.skill("coup") |> Combat.proc(:success)
    daedalus = Combat.item("daedalus") |> Combat.proc(:success)

    result =
      resolve([coup, daedalus], [], nil, nil, fn turn ->
        %{turn | defender: %{turn.defender | base_armor: 10}}
      end)

    # 130 Attack, target Armor 10 - 30 - 40 = -60, hence 60% bonus damage.
    assert result.defender.armor == -60
    assert result.defender.damage == 208
  end

  test "Armor reduction caps at 90%, and pure Laguna bypasses Armor and invulnerability" do
    bolt = Combat.skill("lightning_bolt")
    result = resolve([bolt], [], bolt, nil, &put_in(&1.defender.base_armor, 300))
    assert result.defender.damage == 10
    laguna = Combat.skill("laguna_blade")

    result =
      resolve([laguna], [], laguna, nil, fn turn ->
        %{turn | defender: %{turn.defender | base_armor: 300, invulnerable: true}}
      end)

    assert result.defender.damage == 240
  end

  test "Feast and Jinada trigger for physical skills while Fiery Soul triggers for casts" do
    feast = Combat.skill("feast")
    jinada = Combat.skill("jinada")
    soul = Combat.skill("fiery_soul")
    bolt = Combat.skill("lightning_bolt")
    basic = resolve([feast, jinada, soul])
    assert basic.defender.damage == 114
    assert basic.attacker.hp_regen == 20
    assert basic.attacker.battle_power == 0
    magic = resolve([feast, jinada, soul, bolt], [], bolt)
    assert magic.defender.damage == 102
    assert magic.attacker.hp_regen == 0
    assert magic.attacker.battle_power == 2
  end

  test "Vanguard blocks before Armor and Counter Helix reflects its separate fixed hit" do
    vanguard = Combat.item("vanguard") |> Combat.proc(:success)
    helix = Combat.skill("counter_helix") |> Combat.proc(:success)
    result = resolve([], [vanguard, helix])
    assert result.defender.damage == 76
    assert result.attacker.damage == 50
    assert result.attacker.current_hp == 450
  end

  test "Phase Shift spends Energy and starts its defensive cooldown only on a successful proc" do
    bolt = Combat.skill("lightning_bolt")

    for {outcome, damage, energy} <- [{:success, 0, 96}, {:failure, 100, 100}] do
      phase = Combat.skill("phase_shift") |> Combat.proc(outcome)
      result = resolve([bolt], [phase], bolt)
      assert result.defender.damage == damage
      assert result.defender.current_mp == energy
      assert Map.has_key?(result.defender.future_cooldowns, "phase_shift") == (outcome == :success)
    end
  end

  test "Linken blocks Walrus Punch's stun but still allows its damage" do
    punch = Combat.skill("walrus_punch")
    result = resolve([punch], [Combat.item("linkens_sphere")], punch)
    refute result.defender.stunned
    assert result.defender.damage == 125
    assert result.defender.future_cooldowns["linkens_sphere"] == 5
    assert result.defender.inneffectable
  end

  test "Linken cooling down cannot block a second disable" do
    punch = Combat.skill("walrus_punch")

    result =
      resolve([punch], [Combat.item("linkens_sphere")], punch, nil, fn turn ->
        %{turn | defender: %{turn.defender | cooldowns: %{"linkens_sphere" => 3}}}
      end)

    assert result.defender.stunned
  end

  test "BKB stops status effects, while Borrowed Time converts mitigated incoming damage into healing" do
    punch = Combat.skill("walrus_punch")
    bkb = Combat.item("bkb")

    result =
      resolve([punch], [], punch, nil, fn turn ->
        %{turn | defender: %{turn.defender | defender_buffs: [%Buff{resource: bkb, duration: 1}]}}
      end)

    refute result.defender.stunned
    assert result.defender.damage == 125

    borrowed = Combat.skill("borrowed_time")

    result =
      resolve([punch], [], punch, nil, fn turn ->
        %{
          turn
          | defender: %{
              turn.defender
              | base_armor: 50,
                invulnerable: true,
                defender_buffs: [%Buff{resource: borrowed, duration: 1}]
            }
        }
      end)

    assert result.defender.damage == 0
    assert result.defender.hp_regen == 25
    assert result.defender.current_hp == 825
  end

  test "Battle Trance prevents lethal damage at low Health but cannot stop Culling Blade execution" do
    trance = Combat.skill("battle_trance")
    bolt = Combat.skill("lightning_bolt")

    saved =
      resolve([bolt], [trance], bolt, nil, fn turn ->
        %{turn | defender: %{turn.defender | current_hp: 50}}
      end)

    assert saved.defender.immortal
    assert saved.defender.current_hp == 200
    assert saved.defender.current_mp == 80

    cull = Combat.skill("culling_blade")

    killed =
      resolve([cull], [trance], cull, nil, fn turn ->
        %{turn | defender: %{turn.defender | current_hp: 350, base_armor: 300, invulnerable: true}}
      end)

    assert killed.defender.executed
    assert killed.defender.current_hp == 0
    refute killed.defender.immortal
  end

  test "Culling Blade above the execution threshold deals damage instead" do
    cull = Combat.skill("culling_blade")
    result = resolve([cull], [], cull, nil, &put_in(&1.defender.current_hp, 370))
    refute result.defender.executed
    assert result.defender.damage == 210
    assert result.defender.current_hp == 160
  end

  test "Battle Trance uses actual incoming damage without amplifying Power twice" do
    bolt = Combat.skill("lightning_bolt")
    trance = Combat.skill("battle_trance")

    result =
      resolve([bolt], [trance], bolt, nil, fn turn ->
        %{
          turn
          | attacker: %{turn.attacker | base_power: 100},
            defender: %{turn.defender | current_hp: 350, base_armor: 50}
        }
      end)

    assert result.defender.damage == 100
    assert result.defender.current_hp == 250
    assert result.defender.current_mp == 100
    refute result.defender.immortal
  end

  test "Battle Trance does not trigger from damage that was evaded or blocked by invulnerability" do
    trance = Combat.skill("battle_trance")

    for immunity <- [:evaded, :invulnerable] do
      result =
        resolve([], [trance], nil, nil, fn turn ->
          defender = Map.put(%{turn.defender | current_hp: 250}, immunity, true)
          %{turn | defender: defender}
        end)

      assert result.defender.current_hp == 250
      assert result.defender.current_mp == 100
      refute result.defender.immortal
    end
  end

  test "Blink Strike's ready cooldown entry enables its repeat bonus" do
    blink = Combat.skill("blink_strike")

    result =
      resolve([blink], [], blink, nil, fn turn ->
        %{
          turn
          | attacker: %{turn.attacker | cooldowns: %{"blink_strike" => -1}, future_cooldowns: %{"blink_strike" => -1}}
        }
      end)

    assert result.defender.damage == 190
    assert result.attacker.extra
  end

  test "Double Edge self-damage can kill its caster even when the opponent evades" do
    edge = Combat.skill("double_edge")

    result =
      resolve([edge], [], edge, nil, fn turn ->
        %{turn | attacker: %{turn.attacker | current_hp: 50}, defender: %{turn.defender | evaded: true}}
      end)

    assert result.defender.damage == 0
    assert result.attacker.current_hp <= 0
  end

  test "Time Lapse restores the saved Health and uses previous outgoing damage" do
    lapse = Combat.skill("time_lapse")

    result =
      resolve([lapse], [], lapse, nil, fn turn ->
        %{turn | attacker: %{turn.attacker | last_hp: 650, last_damage_caused: 200}}
      end)

    assert result.attacker.current_hp == 650
    assert result.defender.damage == 70
  end

  test "Diffusal and Mana Burn stack their Energy burn independently of opponent remaining Energy" do
    burn = Combat.skill("mana_burn")
    diffusal = Combat.item("diffusal_blade")
    result = resolve([burn, diffusal], [], burn)
    assert result.defender.mp_burn == 52
    assert result.defender.current_mp == 48
    assert result.defender.damage == 62
    empty = resolve([burn, diffusal], [], burn, nil, &put_in(&1.defender.current_mp, 0))
    assert empty.defender.current_mp == 0
    assert empty.defender.damage == 62
  end

  test "Scythe's active and passive procs stack; its cooldown does not disable the passive" do
    scythe = Combat.item("scythe_of_vyse") |> Combat.proc(:success)
    result = resolve([scythe], [], nil, scythe)
    assert result.defender.stunned
    assert result.attacker.turn_power == 80
    assert result.defender.damage == 180

    cooling =
      resolve([scythe], [], nil, nil, fn turn ->
        %{turn | attacker: %{turn.attacker | cooldowns: %{"scythe_of_vyse" => 4}}}
      end)

    assert cooling.attacker.turn_power == 40
    assert cooling.defender.damage == 140
  end

  test "Satanic heals actual post-mitigation damage and gains no lifesteal from an evaded hit" do
    satanic = Combat.item("satanic")
    result = resolve([satanic], [], nil, satanic, &put_in(&1.defender.base_armor, 50))
    assert result.defender.damage == 59
    assert result.attacker.hp_regen == 59
    missed = resolve([satanic], [], nil, satanic, &put_in(&1.defender.evaded, true))
    assert missed.defender.damage == 0
    assert missed.attacker.hp_regen == 0
  end

  test "Soul Booster and Sages Mask restore separately, with active restoration and natural regeneration" do
    booster = Combat.item("soul_booster")
    mask = Combat.item("sages_mask")
    result = resolve([booster, mask], [], nil, booster)
    assert result.attacker.mp_regen == 33
    assert result.attacker.current_mp == 133
  end

  test "Magic Stick restores both resources and Tranquil Boots cap Health at maximum" do
    stick = Combat.item("magic_stick")
    result = resolve([stick], [], nil, stick)
    assert result.attacker.current_hp == 505
    assert result.attacker.current_mp == 107
    boots = Combat.item("tranquil_boots")
    result = resolve([boots], [], nil, boots, &put_in(&1.attacker.current_hp, 995))
    assert result.attacker.current_hp == 1000
  end

  defp resolve(left, right \\ [], skill \\ nil, item \\ nil, prepare \\ &Function.identity/1) do
    stats = %{total_hp: 1000, total_mp: 200, atk: 100}

    {_, result} =
      Combat.battle(left, right, stats, stats)
      |> Combat.step(skill, item, fn turn ->
        %{
          turn
          | attacker: %{turn.attacker | current_hp: 500, current_mp: 100},
            defender: %{turn.defender | current_hp: 800, current_mp: 100}
        }
        |> prepare.()
      end)

    result
  end
end
