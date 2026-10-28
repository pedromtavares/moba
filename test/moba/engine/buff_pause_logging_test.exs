defmodule Moba.Engine.BuffPauseLoggingTest do
  use ExUnit.Case, async: true

  alias Moba.Engine.Core.{Buff, Logger, Processor, Turns}
  alias Moba.Engine.Schema.{Battler, Turn}
  alias Moba.Game.Schema.{Item, Skill}

  defp hero(attrs \\ %{}) do
    struct(
      Battler,
      Map.merge(
        %{
          name: "Caster",
          total_hp: 1000,
          current_hp: 500,
          total_mp: 100,
          current_mp: 100,
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

  defp skill(code, name, attrs) do
    struct(Skill, Map.merge(%{code: code, name: name, level: 1, cooldown: 5, mp_cost: 10, damage_type: "magic"}, attrs))
  end

  defp paused(attrs \\ %{}) do
    fortune = skill("fortunes_end", "Fortune's End", %{duration: 2})
    hero(Map.merge(%{attacker_debuffs: [%Buff{resource: fortune, duration: 2}]}, attrs))
  end

  defp cast(actor, skill, item \\ nil, target \\ hero(%{name: "Target"})) do
    actor = %{actor | active_skills: List.wrap(skill), active_items: if(item, do: [item], else: [])}

    Processor.process_turn(%Turn{
      number: 1,
      attacker: actor,
      defender: target,
      orders: %{auto: false, skill: skill, item: item}
    })
  end

  # Representative mechanics using dev values, independent of seed balancing.
  for {code, name, attrs} <- [
        {"bad_juju", "Bad Juju", %{power_amount: 8, armor_amount: 8, duration: 5}},
        {"gods_strength", "God's Strength", %{power_amount: 30, duration: 2}},
        {"elder_dragon_form", "Elder Dragon Form", %{base_damage: 15, base_amount: 25, power_amount: 6, duration: 3}},
        {"guardian_angel", "Guardian Angel", %{base_amount: 70, armor_amount: 100, atk_multiplier: 0.0, duration: 2}},
        {"borrowed_time", "Borrowed Time", %{duration: 1}}
      ] do
    @code code
    @name name
    @attrs attrs
    test "#{name} describes a deferred buff without claiming active bonuses" do
      resource = skill(@code, @name, @attrs)
      turn = cast(paused(), resource)
      description = Map.new(Logger.descriptions_for(turn))[@code]
      assert description =~ @name
      assert description =~ "paused"
      refute description =~ "Missing description"
      refute description =~ "invulnerable"
      refute description =~ "gained"
      assert turn.attacker.hp_regen == 0
      assert turn.attacker.next_armor == 0
      assert turn.attacker.turn_power == 0
      refute turn.attacker.invulnerable
      buffs = turn.attacker.buffs ++ turn.attacker.defender_buffs
      assert hd(buffs).duration == resource.duration

      normal = cast(hero(), resource)
      description = Map.new(Logger.descriptions_for(normal))[@code]
      refute description =~ "paused"
      refute description =~ "Missing description"
    end
  end

  test "mixed skills retain immediate damage and explain the deferred buff" do
    empower = skill("empower", "Empower", %{base_damage: 30, atk_multiplier: 1.0, power_amount: 3, duration: 3})
    result = cast(paused(), empower)
    description = Map.new(Logger.descriptions_for(result))["empower"]
    assert description =~ "[damage]50 damage[/damage]"
    assert description =~ "Target"
    assert description =~ "paused"
    refute description =~ "gaining"
    normal = cast(hero(), empower)

    assert Map.new(Logger.descriptions_for(normal))["empower"] ==
             "Deeply energized, Caster dealt [damage]50 damage[/damage] to Target while also [power]gaining 3 Power[/power]"
  end

  test "skipped existing buffs and Pulse Nova emit persisted pause events without charging Energy" do
    empower = skill("empower", "Empower", %{power_amount: 3, duration: 3})
    nova = skill("pulse_nova", "Pulse Nova", %{mp_cost: 6, base_damage: 40, cooldown: 0})
    result = cast(paused(%{buffs: [%Buff{resource: empower, duration: 2}], pulse_nova: nova}), nil)
    descriptions = Map.new(Logger.descriptions_for(result))
    assert descriptions["empower"] =~ "paused"
    assert descriptions["pulse_nova"] =~ "paused"
    assert result.defender.damage == 20
    assert result.attacker.current_mp == 100
    assert hd(result.attacker.buffs).duration == 2
    stored = result |> Turns.serialize() |> Map.fetch!(:attacker) |> Jason.encode!() |> Jason.decode!()
    assert Enum.any?(stored["effects"], &(&1["key"] == "buff_paused"))
  end

  test "BKB activation while paused does not claim immunity" do
    bkb = %Item{code: "bkb", name: "Black King Bar", active: true, mp_cost: 0, cooldown: 5, duration: 1}
    result = cast(paused(), nil, bkb)
    description = Map.new(Logger.descriptions_for(result))["bkb"]
    assert description =~ "Black King Bar"
    assert description =~ "paused"
    refute description =~ "imune"
    refute result.attacker.inneffectable
    assert hd(result.attacker.defender_buffs).duration == 1
  end

  test "suppressed passive bonuses cannot claim active Power" do
    fiery = skill("fiery_soul", "Fiery Soul", %{passive: true, power_amount: 2, mp_cost: 0})
    pulse = skill("death_pulse", "Death Pulse", %{base_damage: 30, base_amount: 20})
    result = cast(paused(%{passive_skills: [fiery]}), pulse)
    description = Map.new(Logger.descriptions_for(result))["fiery_soul"]
    assert description =~ "paused"
    refute description =~ "gained"
    assert result.attacker.battle_power == 0
    assert result.attacker.paused_bonuses["battle_power"] == 2
  end

  test "suppressed defensive procs cannot claim invulnerability" do
    shift = skill("phase_shift", "Phase Shift", %{passive: true, roll_number: 100, mp_cost: 4})
    result = cast(hero(), nil, nil, paused(%{name: "Target", passive_skills: [shift]}))
    description = Map.new(Logger.descriptions_for(result))["phase_shift"]
    assert description =~ "paused"
    refute description =~ "invulnerable"
    refute result.defender.invulnerable
    assert result.defender.damage == 20
    normal = cast(hero(), nil, nil, hero(%{name: "Target", passive_skills: [shift]}))
    assert Map.new(Logger.descriptions_for(normal))["phase_shift"] =~ "invulnerable"
    assert normal.defender.damage == 0
  end

  test "partial descriptions preserve enemy debuffs while the owner's buff is paused" do
    link = skill("static_link", "Static Link", %{base_damage: 30, base_amount: 5, atk_multiplier: 1.1, duration: 2})
    result = cast(paused(), link)
    description = Map.new(Logger.descriptions_for(result))["static_link"]
    assert description =~ "[damage]52 damage[/damage]"
    assert description =~ "Target"
    assert description =~ "Attack"
    assert description =~ "paused"
    assert result.defender.turn_atk == -5
    assert result.attacker.turn_atk == 0
  end

  for code <- ["spell_steal", "rearm"] do
    @code code
    test "#{code} retains its copied skill action while its Power bonus is deferred" do
      copied = skill("death_pulse", "Death Pulse", %{base_damage: 30, base_amount: 20, mp_cost: 0})
      resource = skill(@code, String.upcase(@code), %{power_amount: 10})
      target = hero(%{name: "Target", last_skill: copied})
      actor = paused(%{last_skill: copied})
      result = cast(actor, resource, nil, target)
      descriptions = Map.new(Logger.descriptions_for(result))
      assert descriptions[@code] =~ "Death Pulse"
      assert descriptions[@code] =~ "paused"
      refute descriptions[@code] =~ "gained"
      assert descriptions["death_pulse"] =~ "30"
      assert result.attacker.turn_power == 0
    end
  end

  test "metadata-free saved turns infer deferred buffs without mutating stored effects" do
    effects = [
      %{"key" => "buffs", "value" => "empower", "resource" => "empower", "priority" => 1},
      %{"key" => "mp_regen", "value" => 4, "resource" => "empower", "priority" => 1},
      %{"key" => "spell_count", "value" => 2, "resource" => "empower", "priority" => 1}
    ]

    actor =
      hero(%{
        name: "Leshrac",
        effects: effects,
        paused_bonuses: %{"active" => true},
        buffs: [%{"resource_code" => "empower", "duration" => 3}],
        attacker_debuffs: [%{"resource_code" => "fortunes_end", "duration" => 1}]
      })

    target =
      hero(%{
        name: "PDK",
        effects: [
          %{"key" => "damage", "value" => 60, "resource" => "empower", "priority" => 3},
          %{"key" => "damage", "value" => 33, "resource" => "empower", "priority" => 3}
        ]
      })

    description = Map.new(Logger.descriptions_for(%Turn{attacker: actor, defender: target}))["empower"]
    assert description =~ "[damage]93 damage[/damage]"
    assert description =~ "paused"
    assert actor.effects == effects
  end

  test "legacy defensive logs cannot claim bonuses that were suppressed" do
    actor =
      hero(%{
        paused_bonuses: %{"active" => true, "invulnerable" => true},
        effects: [
          %{"key" => "invulnerable", "value" => true, "resource" => "borrowed_time", "priority" => 1},
          %{"key" => "defender_buffs", "value" => "borrowed_time", "resource" => "borrowed_time", "priority" => 1}
        ],
        defender_buffs: [%{"resource_code" => "borrowed_time", "duration" => 1}]
      })

    description =
      Map.new(Logger.descriptions_for(%Turn{attacker: actor, defender: hero(%{name: "Target"})}))["borrowed_time"]

    assert description =~ "paused"
    refute description =~ "invulnerable"
    refute description =~ "Missing description"
  end

  test "a new partial buff is described from its effects without a resource-specific clause" do
    actor =
      hero(%{
        effects: [
          %{
            "key" => "buffs",
            "value" => "future_buff",
            "resource" => "future_buff",
            "resource_name" => "Future Buff",
            "priority" => 1,
            "paused" => true
          }
        ]
      })

    target =
      hero(%{
        name: "Target",
        effects: [
          %{
            "key" => "damage",
            "value" => 47,
            "resource" => "future_buff",
            "resource_name" => "Future Buff",
            "priority" => 1,
            "paused" => false
          }
        ]
      })

    description = Map.new(Logger.descriptions_for(%Turn{attacker: actor, defender: target}))["future_buff"]
    assert description =~ "Future Buff"
    assert description =~ "[damage]47 damage[/damage]"
    assert description =~ "paused"
    refute description =~ "Missing description"
  end
end
