defmodule MobaWeb.V2.CombatSceneTest do
  use ExUnit.Case, async: true

  alias Moba.Engine.Schema.{Battle, Battler, Turn}
  alias Moba.Game.Schema.{Avatar, Hero}
  alias MobaWeb.V2.Components.CombatScene

  setup do
    left = %Battler{
      hero_id: 1,
      player_id: 10,
      name: "Champion",
      level: 10,
      current_hp: 900,
      total_hp: 1000,
      current_mp: 100,
      total_mp: 200
    }

    right = %Battler{
      hero_id: 2,
      player_id: 20,
      name: "Challenger",
      level: 10,
      current_hp: 800,
      total_hp: 1000,
      current_mp: 0,
      total_mp: 0
    }

    initial = %Turn{attacker: left, defender: right}

    battle = %Battle{
      id: 1,
      type: "duel",
      finished: false,
      attacker_id: 1,
      attacker_player_id: 10,
      defender_id: 2,
      defender_player_id: 20,
      attacker: hero(1),
      defender: hero(2),
      turns: []
    }

    %{initial: initial, battle: battle}
  end

  test "saved action sequence retains side identity, net damage, healing and active items", %{
    initial: initial,
    battle: battle
  } do
    first = %{
      initial
      | number: 1,
        skill: Moba.basic_attack(),
        item: %{code: "dagon", name: "Dagon", image: nil},
        attacker: %{initial.attacker | current_hp: 950},
        defender: %{
          initial.defender
          | current_hp: 500,
            effects: [
              %{"resource" => "basic_attack", "key" => "damage", "value" => 200, "priority" => 0},
              %{"resource" => "dagon", "key" => "damage", "value" => 100, "priority" => 1}
            ]
        }
    }

    second = %Turn{
      number: 2,
      attacker: %{first.defender | current_hp: 510},
      defender: %{first.attacker | current_hp: 700}
    }

    scene = CombatScene.build(%{battle | turns: [first, second]}, initial, initial, %{id: 10})
    [attack, reply] = scene.events
    assert attack.actor == "left"
    assert attack.skill == "Basic Attack + Dagon"
    assert attack.before["left"].hp == 900
    assert attack.after["left"].hp == 950
    assert attack.summary == "Champion used Basic Attack + Dagon · −300 HP"
    assert [%{code: "dagon", name: "Dagon", description: description}] = attack.effects
    assert description =~ "100"
    refute description =~ "[damage]"
    assert reply.actor == "right"
    assert reply.before["left"].hp == 950
    assert reply.after["left"].hp == 700
    assert Enum.map(scene.units, & &1.hp) == [700, 510]
  end

  test "overkill and zero energy stay in range, expired effects are omitted", %{initial: initial, battle: battle} do
    defender = %{
      initial.defender
      | current_hp: -30,
        debuffs: [
          %{"resource_code" => "shuriken_toss", "duration" => 1},
          %{"resource_code" => "decay", "duration" => 0}
        ],
        silenced: true
    }

    turn = %{initial | number: 1, defender: defender}
    scene = CombatScene.build(%{battle | turns: [turn]}, initial, initial, nil)
    right = Enum.find(scene.units, &(&1.side == "right"))
    assert right.hp == 0
    assert right.mp == 0
    assert right.maxMp == 0
    assert Enum.map(right.activeEffects, & &1.code) == ["shuriken_toss"]
    assert List.last(right.activeEffects).duration == 1
    assert List.last(right.activeEffects).tooltip =~ "1 turn remaining"
    assert hd(scene.events).flag == "Finishing blow"
    assert Jason.encode!(scene)
  end

  test "borrowed copies of the same hero are distinguished by their controlling players", %{
    initial: initial,
    battle: battle
  } do
    initial = %{initial | defender: %{initial.defender | hero_id: 1}}
    turn = %Turn{number: 1, attacker: initial.defender, defender: %{initial.attacker | current_hp: 0}}

    battle = %{
      battle
      | defender_id: 1,
        defender: hero(1),
        turns: [turn],
        finished: true,
        winner_id: 1,
        winner_player_id: 20,
        winner: hero(1)
    }

    scene = CombatScene.build(battle, initial, turn, %{id: 20})
    assert scene.winner == "right"
    assert hd(scene.events).actor == "right"
    assert Enum.map(scene.units, & &1.you) == [false, true]
    assert Enum.map(scene.units, & &1.hp) == [0, 800]
  end

  test "current stat totals expose positive and negative modifiers with the engine's percentages", %{
    initial: initial,
    battle: battle
  } do
    initial = %{
      initial
      | attacker: %{
          initial.attacker
          | atk: 150,
            base_atk: 100,
            power: 20,
            base_power: 5,
            armor: -10,
            base_armor: 15,
            total_buff: 0.3,
            pierce_buff: 0.1
        }
    }

    scene = CombatScene.build(battle, initial, initial, %{id: 10})
    stats = hd(scene.units).combatStats |> Map.new(&{&1.key, &1})
    assert stats["attack"].value == 150
    assert stats["attack"].modifier == 50
    assert stats["power"].modifier == 15
    assert stats["power"].tooltip =~ "Damage/Regen Buff: 20%"
    assert stats["armor"].value == -10
    assert stats["armor"].modifier == -25
    assert stats["armor"].tooltip =~ "Extra Damage Taken: 10%"
  end

  test "damage preserves overkill and tooltips escape names while keeping log effect colors", %{
    initial: initial,
    battle: battle
  } do
    turn = %{
      initial
      | number: 1,
        attacker: %{initial.attacker | name: "<b>Champion</b>"},
        defender: %{
          initial.defender
          | current_hp: -400,
            damage: 1200,
            effects: [%{"resource" => "dagon", "key" => "damage", "value" => 1200, "priority" => 1}]
        }
    }

    event = CombatScene.build(%{battle | turns: [turn]}, initial, initial, nil).events |> hd()
    assert event.damage == 1200
    refute event.tooltip =~ "<b>Champion</b>"
    assert event.tooltip =~ "&lt;b&gt;Champion&lt;/b&gt;"
    assert hd(event.effects).tooltip =~ "text-danger"
  end

  defp hero(id), do: %Hero{id: id, name: "Hero #{id}", avatar: %Avatar{name: "Avatar"}}

  test "ongoing effects merge durations into triggered icons without duplicating the primary skill" do
    event = %{code: "empower", effects: [%{code: "dagon", name: "Dagon", tooltip: "Dealt 75 damage"}]}

    active = [
      %{code: "empower", duration: 2, kind: "buff", tooltip: "2 turns remaining"},
      %{code: "dagon", duration: 1, kind: "debuff", tooltip: "1 turn remaining"},
      %{code: "shuriken_toss", duration: 3, kind: "debuff", tooltip: "3 turns remaining"}
    ]

    assert [dagon, shuriken] = CombatScene.display_effects(event, active)
    assert dagon.duration == 1
    assert dagon.tooltip =~ "Dealt 75 damage"
    assert dagon.tooltip =~ "1 turn remaining"
    assert shuriken.code == "shuriken_toss"
    assert shuriken.duration == 3
  end

  test "both saved loadouts use the normal active/passive order with the ultimate last", %{
    initial: initial,
    battle: battle
  } do
    skills = [
      %Moba.Game.Schema.Skill{id: 1, code: "ultimate", name: "Ultimate", ultimate: true},
      %Moba.Game.Schema.Skill{id: 2, code: "zeta", name: "Zeta"},
      %Moba.Game.Schema.Skill{id: 3, code: "passive", name: "Passive", passive: true},
      %Moba.Game.Schema.Skill{id: 4, code: "alpha", name: "Alpha"}
    ]

    snapshot = %{"skills" => Enum.map(skills, &Ecto.embedded_dump(&1, :json)), "items" => []}
    battle = %{battle | loadouts: %{"1" => snapshot, "2" => snapshot}}
    scene = CombatScene.build(battle, initial, initial, nil)

    for unit <- scene.units do
      assert Enum.map(unit.build.skills, & &1.name) == ["Alpha", "Zeta", "Passive", "Ultimate"]
      assert Enum.map(unit.build.skills, & &1.code) == ["alpha", "zeta", "passive", "ultimate"]
    end
  end

  test "build cooldowns follow both heroes through saved actions, reductions and resets", %{
    initial: initial,
    battle: battle
  } do
    initial = %{
      initial
      | attacker: %{initial.attacker | cooldowns: %{"omnislash" => 2, "dagon" => 0}},
        defender: %{initial.defender | cooldowns: %{"laguna_blade" => 1}}
    }

    first = %{
      initial
      | number: 1,
        attacker: %{initial.attacker | cooldowns: %{"omnislash" => 1, "dagon" => -1}}
    }

    second = %Turn{
      number: 2,
      attacker: %{first.defender | cooldowns: %{}},
      defender: first.attacker
    }

    scene = CombatScene.build(%{battle | turns: [first, second]}, initial, second, nil)
    [attack, reply] = scene.events
    assert attack.before["left"].cooldowns == %{"omnislash" => 3, "dagon" => 1}
    assert attack.after["left"].cooldowns == %{"omnislash" => 2, "dagon" => 0}
    assert attack.after["right"].cooldowns == %{"laguna_blade" => 2}
    assert reply.before["right"].cooldowns == %{"laguna_blade" => 2}
    assert reply.after["right"].cooldowns == %{}
    assert Enum.find(scene.units, &(&1.side == "left")).cooldowns == attack.after["left"].cooldowns
    assert Enum.find(scene.units, &(&1.side == "right")).cooldowns == %{}
  end

  test "charging and invulnerability use their actual skill artwork without generic status icons", %{
    initial: initial,
    battle: battle
  } do
    echo = %Moba.Game.Schema.Skill{
      id: 91,
      name: "Echo Stomp",
      code: "echo_stomp",
      image: %{file_name: "echo_stomp.png", updated_at: nil}
    }

    borrowed = %Moba.Game.Schema.Skill{
      id: 92,
      name: "Borrowed Time",
      code: "borrowed_time",
      image: %{file_name: "borrowed_time.png", updated_at: nil},
      ultimate: true
    }

    initial = %{
      initial
      | attacker: %{initial.attacker | active_skills: [echo]},
        defender: %{initial.defender | passive_skills: [borrowed]}
    }

    turn = %{
      initial
      | number: 1,
        skill: echo,
        attacker: %{
          initial.attacker
          | charging: true,
            double_skill_code: "echo_stomp",
            effects: [%{"resource" => "echo_stomp", "key" => "charging", "value" => true, "priority" => 1}]
        },
        defender: %{
          initial.defender
          | invulnerable: true,
            defender_buffs: [%{"resource_code" => "borrowed_time", "duration" => 2}],
            effects: [%{"resource" => "borrowed_time", "key" => "invulnerable", "value" => true, "priority" => 1}]
        }
    }

    scene = CombatScene.build(%{battle | turns: [turn]}, initial, initial, nil)
    assert hd(scene.events).flag == "Charging"
    [left, right] = scene.units
    assert [%{code: "echo_stomp", image: image, tooltip: text}] = left.activeEffects
    assert image =~ "echo_stomp.png"
    assert text =~ "charging"
    assert [%{code: "borrowed_time", duration: 2, image: borrowed_image, tooltip: borrowed_text}] = right.activeEffects
    assert borrowed_image =~ "borrowed_time.png"
    assert borrowed_text =~ "invulnerable"
    refute Enum.any?(left.activeEffects ++ right.activeEffects, &(&1.code in ["charging", "invulnerable"]))
  end

  test "stun, silence and disarm visuals follow saved flags even without a source icon", %{
    initial: initial,
    battle: battle
  } do
    first = %{
      initial
      | number: 1,
        attacker: %{initial.attacker | stunned: true, disarmed: true},
        defender: %{initial.defender | silenced: true}
    }

    second = %Turn{
      number: 2,
      attacker: %{first.defender | silenced: false},
      defender: %{first.attacker | stunned: false, disarmed: false}
    }

    scene = CombatScene.build(%{battle | turns: [first, second]}, initial, second, nil)
    [applied, expired] = scene.events
    assert applied.before["left"].statuses == %{stunned: false, silenced: false, disarmed: false}
    assert applied.after["left"].statuses == %{stunned: true, silenced: false, disarmed: true}
    assert applied.after["right"].statuses == %{stunned: false, silenced: true, disarmed: false}
    assert expired.before["left"].statuses.disarmed
    assert expired.before["left"].statuses.stunned
    assert expired.before["right"].statuses.silenced
    refute expired.after["left"].statuses.disarmed
    refute expired.after["left"].statuses.stunned
    refute expired.after["right"].statuses.silenced
    assert Enum.all?(scene.units, &(&1.statuses == %{stunned: false, silenced: false, disarmed: false}))
  end
end
