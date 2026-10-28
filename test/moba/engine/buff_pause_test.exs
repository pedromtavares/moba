defmodule Moba.Engine.BuffPauseTest do
  use Moba.DataCase

  alias Moba.Engine.Core.{Buff, BuffPause, Helper, Logger, Processor, Turns}
  alias Moba.Engine.Schema.{Battle, Turn}
  alias Moba.Game.Schema.Skill

  setup do
    key = "resources-#{Game.current_season().resource_uuid}"
    Cachex.del(:game_cache, key)
    on_exit(fn -> Cachex.del(:game_cache, key) end)

    fortune = insert_skill("fortunes_end", %{base_damage: 40, duration: 2, cooldown: 5, mp_cost: 12})
    chakra = insert_skill("chakra_magic", %{base_amount: 10, extra_amount: 1, cooldown: 6})
    nova = insert_skill("pulse_nova", %{base_damage: 40, mp_cost: 6, cooldown: 0, ultimate: true})
    %{fortune: fortune, chakra: chakra, nova: nova}
  end

  defp insert_skill(code, attrs) do
    Repo.insert!(
      struct(
        Skill,
        Map.merge(
          %{
            code: code,
            name: code,
            current: true,
            enabled: true,
            level: 1,
            resource_uuid: Game.current_season().resource_uuid,
            mp_cost: 0,
            damage_type: "magic"
          },
          attrs
        )
      )
    )
  end

  defp battle(skills, enemy_skills) do
    hero = fn skills ->
      hero =
        Game.Heroes.create!(%{name: "Pause playtest", total_hp: 5000, total_mp: 1000, atk: 20}, nil, base_avatar(), [])

      hero = Game.Heroes.update!(hero, %{}, nil, skills)
      Repo.update!(change(hero, power: 0, armor: 0, speed: 0))
    end

    attacker = hero.(skills)
    defender = hero.(enemy_skills)

    stored =
      Repo.insert!(%Battle{
        attacker_id: attacker.id,
        defender_id: defender.id,
        initiator_id: attacker.id,
        type: "playtest",
        finished: false
      })

    %{
      stored
      | attacker: attacker,
        defender: defender,
        initiator: attacker,
        turns: [],
        attacker_player: nil,
        defender_player: nil,
        initiator_player: nil
    }
  end

  defp step(battle, skill \\ nil, prepare \\ &Function.identity/1) do
    turn = battle |> Turns.build_turn(%{auto: false, skill: skill, item: nil}) |> prepare.() |> Processor.process_turn()
    saved = turn |> Turns.serialize() |> Repo.insert!()
    stored = Repo.get!(Turn, saved.id)
    {%{battle | turns: battle.turns ++ [stored]}, turn}
  end

  test "Sven keeps his unused empowered attacks through two saved opponent turns", %{fortune: fortune} do
    strength = Game.get_skill_by_code!("gods_strength", true, 1)
    {battle, cast} = battle([strength], [fortune]) |> step(strength)
    remaining = hd(cast.attacker.buffs).duration
    power = cast.attacker.next_power_normal
    assert power > 0
    {battle, paused} = step(battle, fortune)
    assert paused.defender.next_power_normal == 0
    assert paused.defender.paused_bonuses["next_power_normal"] == power
    assert hd(paused.defender.buffs).duration == remaining
    {battle, first} = step(battle)
    assert first.defender.damage == 20
    assert hd(first.attacker.buffs).duration == remaining
    assert BuffPause.paused?(first.attacker)
    {battle, _} = step(battle)
    {battle, second} = step(battle)
    assert second.defender.damage == 20
    refute BuffPause.paused?(second.attacker)
    assert hd(second.attacker.buffs).duration == remaining
    assert Map.new(Logger.descriptions_for(second))["fortunes_end"] =~ "buffs resumed"
    {battle, _} = step(battle)
    {_battle, resumed} = step(battle)
    assert resumed.defender.damage == round(20 * (1 + power / 100))
    assert hd(resumed.attacker.buffs).duration == remaining - 1
  end

  test "Chakra immediately restores paused healing and Armor, consuming one cleanse slot", %{
    fortune: fortune,
    chakra: chakra
  } do
    angel = Game.get_skill_by_code!("guardian_angel", true, 1)

    {battle, cast} =
      battle([angel, chakra], [fortune])
      |> step(angel, fn turn ->
        %{turn | attacker: %{turn.attacker | current_hp: 1000}}
      end)

    remaining = hd(cast.attacker.buffs).duration
    {battle, _} = step(battle, fortune)
    {_battle, cleansed} = step(battle, chakra)
    refute BuffPause.paused?(cleansed.attacker)
    assert cleansed.attacker.attacker_debuffs == []
    assert cleansed.attacker.hp_regen == angel.base_amount
    descriptions = Map.new(Logger.descriptions_for(cleansed))
    assert descriptions["fortunes_end"] =~ "buffs resumed"
    assert descriptions["guardian_angel"] =~ "regenerating"
    refute descriptions["guardian_angel"] =~ "paused"
    assert Helper.total_armor(cleansed.attacker) >= angel.armor_amount
    assert hd(cleansed.attacker.buffs).duration == remaining - 1
  end

  test "Abaddon's defensive buff freezes, then resumes on the next incoming attack", %{fortune: fortune} do
    borrowed = Game.get_skill_by_code!("borrowed_time", true, 1)

    {battle, _} =
      battle([borrowed], [fortune])
      |> step(borrowed, fn turn ->
        %{turn | attacker: %{turn.attacker | current_hp: 1000}}
      end)

    {battle, paused} = step(battle, fortune)
    remaining = hd(paused.defender.defender_buffs).duration
    assert paused.defender.damage == 40
    refute paused.defender.invulnerable
    {battle, _} = step(battle)
    {battle, incoming} = step(battle)
    assert incoming.defender.damage == 20
    assert incoming.defender.hp_regen == 0
    assert hd(incoming.defender.defender_buffs).duration == remaining
    {battle, _} = step(battle)
    {_battle, resumed} = step(battle)
    assert resumed.defender.damage == 0
    assert resumed.defender.hp_regen > 0
    assert hd(resumed.defender.defender_buffs).duration == remaining - 1
  end

  test "Pulse Nova keeps its state and Energy while paused, then automatically resumes", %{fortune: fortune, nova: nova} do
    {battle, activated} =
      battle([nova], [fortune])
      |> step(nova, fn turn ->
        %{turn | attacker: %{turn.attacker | total_mp: 100, current_mp: 100}}
      end)

    {battle, _} = step(battle, fortune)
    {battle, first} = step(battle)
    assert first.attacker.pulse_nova
    assert first.defender.damage == 20
    assert first.attacker.current_mp == activated.attacker.current_mp + first.attacker.mp_regen
    {battle, _} = step(battle)
    {battle, second} = step(battle)
    assert second.defender.damage == 20
    assert second.attacker.current_mp == first.attacker.current_mp + second.attacker.mp_regen
    {battle, _} = step(battle)
    {_battle, resumed} = step(battle)
    assert resumed.defender.damage == 20 + nova.base_damage
    assert resumed.attacker.current_mp == second.attacker.current_mp + resumed.attacker.mp_regen - nova.mp_cost
  end

  test "Chakra resumes Nova once, using the Energy it restores", %{fortune: fortune, nova: nova, chakra: chakra} do
    {battle, _} = battle([nova, chakra], [fortune]) |> step(nova)
    {battle, _} = step(battle, fortune)

    {_battle, resumed} =
      step(battle, chakra, fn turn ->
        %{turn | attacker: %{turn.attacker | current_mp: 0}}
      end)

    refute BuffPause.paused?(resumed.attacker)
    assert resumed.attacker.pulse_nova
    assert resumed.defender.damage == nova.base_damage
    assert resumed.attacker.current_mp == resumed.attacker.mp_regen - nova.mp_cost
  end

  test "buffs gained during the pause wait with their full duration", %{fortune: fortune} do
    strength = Game.get_skill_by_code!("gods_strength", true, 1)
    {battle, _} = battle([strength], [fortune]) |> step()
    {battle, _} = step(battle, fortune)
    {battle, waiting} = step(battle, strength)
    assert hd(waiting.attacker.buffs).duration == strength.duration
    assert waiting.attacker.next_power_normal == 0
    {battle, _} = step(battle)
    {battle, _} = step(battle)
    {battle, _} = step(battle)
    {_battle, resumed} = step(battle)
    assert hd(resumed.attacker.buffs).duration == strength.duration - 1
    assert resumed.attacker.next_power_normal == strength.power_amount
  end

  test "Empower logs its damage while paused and its Power when the buff resumes", %{fortune: fortune} do
    empower =
      Game.get_skill_by_code!("empower", true, 3)
      |> change(base_damage: 60, atk_multiplier: 1.0, power_amount: 9, duration: 3, damage_type: "normal")
      |> Repo.update!()

    {battle, _} = battle([empower], [fortune]) |> step()
    {battle, _} = step(battle, fortune)
    {battle, cast} = step(battle, empower)
    description = Map.new(Logger.descriptions_for(cast))["empower"]
    assert description =~ "[damage]#{empower.base_damage + 20} damage[/damage]"
    assert description =~ "paused"
    stored_description = Map.new(Logger.descriptions_for(List.last(battle.turns)))["empower"]
    assert stored_description == description
    assert cast.attacker.turn_power == 0
    assert hd(cast.attacker.buffs).duration == empower.duration
    {battle, _} = step(battle)
    {battle, _} = step(battle)
    {battle, _} = step(battle)
    {_battle, resumed} = step(battle)
    description = Map.new(Logger.descriptions_for(resumed))["empower"]
    assert description =~ "[power]gained #{empower.power_amount} Power[/power]"
    assert resumed.attacker.turn_power == empower.power_amount
    assert hd(resumed.attacker.buffs).duration == empower.duration - 1
  end

  test "Dazzle's ramp freezes and a cleanse on the last paused turn resumes it once", %{
    fortune: fortune,
    chakra: chakra
  } do
    juju = Game.get_skill_by_code!("bad_juju", true, 1)
    {battle, cast} = battle([juju, chakra], [fortune]) |> step(juju)
    initial = hd(cast.attacker.buffs)
    {battle, _} = step(battle, fortune)
    {battle, frozen} = step(battle)
    assert hd(frozen.attacker.buffs).power == initial.power
    assert hd(frozen.attacker.buffs).armor == initial.armor
    {battle, _} = step(battle)
    {battle, resumed} = step(battle, chakra)
    refute BuffPause.paused?(resumed.attacker)
    assert hd(resumed.attacker.buffs).duration == initial.duration - 1
    assert hd(resumed.attacker.buffs).power == initial.power + juju.power_amount
    assert resumed.attacker.turn_armor == cast.attacker.next_armor
    assert resumed.attacker.next_armor == initial.armor + juju.armor_amount
    {_battle, defense} = step(battle)
    assert defense.defender.turn_armor == 0
    assert defense.defender.next_armor == resumed.attacker.next_armor
  end

  test "Nova activated during the pause waits without an initial pulse or charge", %{fortune: fortune, nova: nova} do
    {battle, _} = battle([nova], [fortune]) |> step()
    {battle, _} = step(battle, fortune)

    {battle, waiting} =
      step(battle, nova, fn turn ->
        %{turn | attacker: %{turn.attacker | total_mp: 100, current_mp: 50}}
      end)

    assert waiting.attacker.pulse_nova
    assert waiting.defender.damage == 0
    assert waiting.attacker.current_mp == 50 + waiting.attacker.mp_regen
    {battle, _} = step(battle)
    {battle, _} = step(battle)
    {battle, _} = step(battle)
    {_battle, resumed} = step(battle)
    assert resumed.defender.damage == 20 + nova.base_damage
    assert resumed.attacker.pulse_nova
  end

  test "suppression preserves negative penalties and base stats, and refreshes without stacking", %{fortune: fortune} do
    battler = %Moba.Engine.Schema.Battler{
      base_atk: 20,
      base_armor: 15,
      base_power: 25,
      battle_power: -10,
      next_armor: 30,
      attacker_debuffs: [%Buff{resource: fortune, duration: 2}]
    }

    paused = BuffPause.suppress(battler)
    assert paused.battle_power == -10
    assert Helper.total_power(paused) == 15
    assert Helper.total_armor(paused) == 15
    restored = BuffPause.resume(%{paused | attacker_debuffs: []})
    assert restored.next_armor == 30
    assert restored.battle_power == -10

    turn = %Turn{attacker: battler, defender: paused, resource: fortune}
    refreshed = Moba.Engine.Core.Effect.pause_opponent_buffs(turn)
    assert length(refreshed.defender.attacker_debuffs) == 1
    assert hd(refreshed.defender.attacker_debuffs).duration == 2
    assert refreshed.defender.paused_bonuses["next_armor"] == 30
  end
end
