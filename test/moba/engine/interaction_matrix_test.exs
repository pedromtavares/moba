defmodule Moba.Engine.SkillItemMatrixTest do
  use ExUnit.Case, async: true

  alias Test.CombatCase, as: Combat
  alias Moba.Engine.Core.Logger

  @moduletag :interaction_matrix

  for skill <- Combat.skills() do
    @skill skill
    test "#{skill.code} with every item, proc branch, and availability boundary" do
      for item <- Combat.items(),
          skill_outcome <- Combat.outcomes(@skill),
          item_outcome <- Combat.outcomes(item),
          state <- [:ready, :no_energy, :cooling_down] do
        label = {@skill.code, @skill.level, item.code, skill_outcome, item_outcome, state}
        Combat.seed(label)
        skill = Combat.proc(@skill, skill_outcome)
        item = Combat.proc(item, item_outcome)
        {selected_skill, _} = Combat.chosen(skill)
        {_, selected_item} = Combat.chosen(item)

        prepare = fn turn ->
          cooldowns = if state == :cooling_down, do: %{skill.code => 2, item.code => 2}, else: %{}
          mp = if state == :no_energy, do: 0, else: turn.attacker.current_mp

          %{
            turn
            | attacker: %{
                turn.attacker
                | current_hp: 5000,
                  current_mp: mp,
                  cooldowns: cooldowns,
                  future_cooldowns: cooldowns
              }
          }
        end

        {_, result} = Combat.battle([skill, item], [item]) |> Combat.step(selected_skill, selected_item, prepare)
        assert_sound(result, label)

        if state == :ready do
          assert result.skill.code == ((selected_skill && selected_skill.code) || "basic_attack"),
                 inspect(label)

          assert result.item == selected_item, inspect(label)
        end

        if state == :no_energy && (skill.mp_cost || 0) > 0 do
          assert result.skill.code == "basic_attack", inspect(label)
        end

        if state == :cooling_down do
          assert result.skill.code == "basic_attack", inspect(label)
          assert is_nil(result.item), inspect(label)
        end
      end
    end
  end

  for item <- Combat.items() do
    @item item
    test "#{item.code} combines with every other item and both proc outcomes" do
      for other <- Combat.items(),
          other.code != @item.code,
          first_outcome <- Combat.outcomes(@item),
          second_outcome <- Combat.outcomes(other) do
        label = {@item.code, other.code, first_outcome, second_outcome}
        Combat.seed(label)
        first = Combat.proc(@item, first_outcome)
        second = Combat.proc(other, second_outcome)
        {_, selected} = Combat.chosen(first)
        {_, result} = Combat.battle([first, second], [second]) |> Combat.step(nil, selected)
        assert_sound(result, label)
      end
    end
  end

  defp assert_sound(turn, label) do
    for battler <- [turn.attacker, turn.defender] do
      assert is_integer(battler.current_hp) && battler.current_hp <= battler.total_hp, inspect(label)
      assert battler.current_mp in 0..battler.total_mp, inspect(label)
      assert is_integer(battler.damage) && battler.damage >= 0, inspect(label)
      assert is_integer(battler.hp_regen) && battler.hp_regen >= 0, inspect(label)
      assert is_integer(battler.mp_regen) && battler.mp_regen >= 0, inspect(label)
    end

    for {_, description} <- Logger.descriptions_for(turn) do
      refute description =~ "Missing description", "#{inspect(label)}: #{description}"
    end
  end
end
