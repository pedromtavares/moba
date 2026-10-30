defmodule Moba.Engine.SpellCopyInteractionsTest do
  use Moba.DataCase

  alias Test.CombatCase, as: Combat
  alias Moba.Engine.Core.Logger

  setup do
    Combat.install_catalog()
    :ok
  end

  for copied <- Combat.skills(), !copied.passive, copied.code != "spell_steal" do
    @copied copied
    test "Rubick copies #{@copied.code} without charging its cost or giving it a cooldown" do
      steal = Combat.skill("spell_steal")
      copied = Combat.proc(@copied, :success)
      Combat.seed({:steal, copied.code})

      {_, result} =
        Combat.battle([steal], [copied])
        |> Combat.step(steal, nil, fn turn ->
          %{
            turn
            | attacker: %{turn.attacker | current_mp: steal.mp_cost},
              defender: %{turn.defender | last_skill: copied}
          }
        end)

      assert result.skill.code == "spell_steal"
      assert result.attacker.spell_count == 1
      assert result.attacker.bonus == copied.name
      assert Map.keys(result.attacker.cooldowns) == ["spell_steal"]
      assert costs(result) == [-steal.mp_cost]
      assert Enum.any?(result.attacker.effects ++ result.defender.effects, &(&1["resource"] == copied.code))
      assert_readable(result)
    end
  end

  for copied <- Combat.skills(), !copied.passive, copied.code != "rearm" do
    @copied copied
    test "Rearm repeats #{@copied.code}, pays both costs, and resets previous cooldowns" do
      rearm = Combat.skill("rearm")
      copied = Combat.proc(@copied, :success)
      Combat.seed({:rearm, copied.code})

      {_, result} =
        Combat.battle([rearm, copied], [Combat.skill("lightning_bolt")])
        |> Combat.step(rearm, nil, fn turn ->
          cds = %{copied.code => 4, "old_item" => 5}

          %{
            turn
            | attacker: %{turn.attacker | last_skill: copied, cooldowns: cds, future_cooldowns: cds},
              defender: %{turn.defender | last_skill: Combat.skill("lightning_bolt")}
          }
        end)

      assert result.skill.code == "rearm"
      assert result.attacker.spell_count == 2
      assert result.attacker.bonus == copied.name
      assert costs(result) == [-copied.mp_cost, -rearm.mp_cost]
      assert Enum.sort(Map.keys(result.attacker.cooldowns)) == Enum.sort([copied.code, "rearm"])
      assert_readable(result)
    end
  end

  test "Rubick uses his Power for Sunder and only pays Spell Steal's initial cost" do
    steal = Combat.skill("spell_steal")
    sunder = Combat.skill("sunder")

    {_, result} =
      Combat.battle([steal], [sunder])
      |> Combat.step(steal, nil, fn turn ->
        %{
          turn
          | attacker: %{turn.attacker | current_hp: 500, current_mp: 10},
            defender: %{turn.defender | current_hp: 1000, last_skill: sunder}
        }
      end)

    assert result.attacker.current_hp == 622
    assert result.defender.current_hp == 878
    assert result.attacker.current_mp == 10
    assert result.attacker.next_power == 22
  end

  test "Rearm amplifies Sunder once, charging both casts and restoring both cast regenerations" do
    rearm = Combat.skill("rearm")
    sunder = Combat.skill("sunder")

    {_, result} =
      Combat.battle([rearm, sunder])
      |> Combat.step(rearm, nil, fn turn ->
        %{
          turn
          | attacker: %{turn.attacker | last_skill: sunder, current_hp: 500, current_mp: 100},
            defender: %{turn.defender | current_hp: 1000}
        }
      end)

    assert result.attacker.current_hp == 610
    assert result.defender.current_hp == 890
    assert result.attacker.current_mp == 78
  end

  test "Rearm with insufficient combined Energy resets cooldowns and attacks without repeating" do
    rearm = Combat.skill("rearm")
    laguna = Combat.skill("laguna_blade")

    {_, result} =
      Combat.battle([rearm, laguna])
      |> Combat.step(rearm, nil, fn turn ->
        %{
          turn
          | attacker: %{
              turn.attacker
              | last_skill: laguna,
                current_mp: 39,
                cooldowns: %{"old_item" => 5},
                future_cooldowns: %{"old_item" => 5}
            }
        }
      end)

    assert result.defender.damage == 40
    assert result.attacker.spell_count == 1
    assert costs(result) == [-20]
    assert result.attacker.cooldowns == %{"rearm" => 4}
  end

  test "Rubick cannot copy himself and Rearm cannot repeat itself" do
    for code <- ["spell_steal", "rearm"] do
      skill = Combat.skill(code)

      {_, result} =
        Combat.battle([skill], [skill])
        |> Combat.step(skill, nil, fn turn ->
          %{turn | attacker: %{turn.attacker | last_skill: skill}, defender: %{turn.defender | last_skill: skill}}
        end)

      assert result.defender.damage == 40
      assert result.attacker.spell_count == 1
      assert costs(result) == [-skill.mp_cost]
    end
  end

  test "Rearm repeating Spell Steal against Rearm resolves without recursively reusing its own history" do
    parent = self()
    rearm = Combat.skill("rearm")
    steal = Combat.skill("spell_steal")

    task =
      Task.async(fn ->
        result =
          Combat.battle([rearm, steal], [rearm])
          |> Combat.step(rearm, nil, fn turn ->
            %{turn | attacker: %{turn.attacker | last_skill: steal}, defender: %{turn.defender | last_skill: rearm}}
          end)

        send(parent, {:copy_cycle_resolved, result})
      end)

    finished = Task.yield(task, 1000) || Task.shutdown(task, :brutal_kill)
    assert finished, "Rearm/Spell Steal entered an unbounded copy cycle"
    assert_received {:copy_cycle_resolved, {_, result}}
    assert result.attacker.spell_count == 2
    assert costs(result) == [-10, -20]
    assert result.defender.damage > 0
    assert_readable(result)
  end

  for code <- ~w(illuminate echo_stomp assassinate life_drain blade_fury remote_mines dream_coil psionic_trap) do
    @code code
    test "a stolen #{@code} survives JSON saving and resolves on Rubick's next turn" do
      steal = Combat.skill("spell_steal")
      copied = Combat.skill(@code)

      {battle, first} =
        Combat.battle([steal], [copied])
        |> Combat.step(steal, nil, fn turn ->
          %{turn | defender: %{turn.defender | last_skill: copied}}
        end)

      {battle, _} = Combat.step(battle)
      {_, next} = Combat.step(battle)

      assert Enum.any?(next.attacker.effects ++ next.defender.effects, &(&1["resource"] == copied.code)),
             "#{copied.code} disappeared after saving because Rubick doesn't own it"

      assert next.defender.damage > 0
      assert costs(next) == []

      if copied.code in ~w(illuminate echo_stomp assassinate life_drain blade_fury) do
        assert first.attacker.double_skill.code == copied.code
        assert is_nil(next.attacker.double_skill)
      end

      assert_readable(next)
    end
  end

  test "copied Pulse Nova persists, burns its own Energy on later turns, and is not duplicated by Rearm" do
    steal = Combat.skill("spell_steal")
    nova = Combat.skill("pulse_nova")
    rearm = Combat.skill("rearm")

    {battle, first} =
      Combat.battle([steal, rearm], [nova])
      |> Combat.step(steal, nil, fn turn ->
        %{turn | attacker: %{turn.attacker | current_mp: 100}, defender: %{turn.defender | last_skill: nova}}
      end)

    assert first.attacker.pulse_nova == nova
    {battle, _} = Combat.step(battle)
    {_, next} = Combat.step(battle, rearm)
    assert next.attacker.pulse_nova.code == "pulse_nova"
    assert Enum.count(next.attacker.effects, &(&1["resource"] == "pulse_nova" && &1["key"] == :current_mp)) == 1
  end

  test "a copied channel keeps its source rank even when Rubick owns a lower-ranked version" do
    steal = Combat.skill("spell_steal")
    owned = Combat.skill("illuminate")
    copied = %{owned | level: 3, base_damage: 731}
    key = "resources-#{Game.current_season().resource_uuid}"
    Cachex.put(:game_cache, key, Combat.resources() ++ [copied])

    {battle, _} =
      Combat.battle([steal, owned], [copied])
      |> Combat.step(steal, nil, fn turn ->
        %{turn | defender: %{turn.defender | last_skill: copied}}
      end)

    assert hd(battle.turns).attacker.double_skill_level == 3
    {battle, _} = Combat.step(battle)
    {_, result} = Combat.step(battle)
    assert result.skill.level == 3
    assert result.defender.damage == 892
  end

  test "saved channels from before rank metadata was introduced still resolve" do
    channel = Combat.skill("illuminate")
    {battle, _} = Combat.battle([channel]) |> Combat.step(channel)
    [saved] = battle.turns
    saved = %{saved | attacker: %{saved.attacker | double_skill_level: nil}}
    {battle, _} = Combat.step(%{battle | turns: [saved]})
    {_, result} = Combat.step(battle)
    assert result.defender.damage == 250
    assert is_nil(result.attacker.double_skill)
  end

  test "a stolen channel interrupted by stun deals its partial damage once without charging Energy" do
    steal = Combat.skill("spell_steal")
    channel = Combat.skill("illuminate")
    punch = Combat.skill("walrus_punch")

    {battle, _} =
      Combat.battle([steal], [channel, punch])
      |> Combat.step(steal, nil, fn turn ->
        %{turn | defender: %{turn.defender | last_skill: channel}}
      end)

    {battle, _} = Combat.step(battle, punch)
    {_, interrupted} = Combat.step(battle)
    assert interrupted.defender.damage == 153
    assert costs(interrupted) == []
    assert is_nil(interrupted.attacker.double_skill)
    assert_readable(interrupted)
  end

  test "Rearm fires an already queued Dream Coil and schedules a fresh delayed cast" do
    rearm = Combat.skill("rearm")
    coil = Combat.skill("dream_coil")
    {battle, _} = Combat.battle([rearm, coil]) |> Combat.step(coil)
    {battle, _} = Combat.step(battle)
    {battle, repeated} = Combat.step(battle, rearm)
    assert repeated.defender.damage == 110
    assert repeated.attacker.delayed_skill.code == "dream_coil"
    assert costs(repeated) == [-20, -20]
    {battle, _} = Combat.step(battle)
    {_, next} = Combat.step(battle)
    assert next.defender.damage == 140
    assert is_nil(next.attacker.delayed_skill)
  end

  defp costs(turn), do: turn.attacker.effects |> Enum.filter(&(&1["key"] == :current_mp)) |> Enum.map(& &1["value"])

  defp assert_readable(turn) do
    for {_, description} <- Logger.descriptions_for(turn), do: refute(description =~ "Missing description")
  end
end
