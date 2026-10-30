defmodule Moba.Engine.OpposingResourceMatrixTest do
  use Moba.DataCase

  alias Test.CombatCase, as: Combat
  alias Moba.Engine.Core.Logger

  @moduletag :interaction_matrix

  setup do
    Combat.install_catalog()
    :ok
  end

  for first <- Combat.resources() do
    @first first
    test "#{first.code} against every skill/item over six saved turns" do
      for second <- Combat.resources(),
          first_outcome <- Combat.outcomes(@first),
          second_outcome <- Combat.outcomes(second) do
        label = {@first.code, second.code, first_outcome, second_outcome}
        Combat.seed(label)
        first = Combat.proc(@first, first_outcome)
        second = Combat.proc(second, second_outcome)
        battle = Combat.battle([first], [second])

        Enum.reduce(1..6, battle, fn number, battle ->
          resource = if rem(number, 2) == 1, do: first, else: second
          {skill, item} = Combat.chosen(resource)
          {battle, result} = Combat.step(battle, skill, item)

          for battler <- [result.attacker, result.defender] do
            assert is_integer(battler.current_hp) && battler.current_hp <= battler.total_hp, inspect({label, number})
            assert battler.current_mp in 0..battler.total_mp, inspect({label, number})
            assert is_integer(battler.damage) && battler.damage >= 0, inspect({label, number})
          end

          for {_, description} <- Logger.descriptions_for(result) do
            refute description =~ "Missing description", "#{inspect({label, number})}: #{description}"
          end

          battle
        end)
      end
    end
  end
end
