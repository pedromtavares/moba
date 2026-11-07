defmodule Moba.Engine.CombatPersistenceTest do
  use ExUnit.Case, async: true
  alias Test.CombatCase, as: Combat

  # All resources still cross the real JSON persistence boundary, independently
  # of the exhaustive pair matrix. Both paths must produce identical persisted state.
  for resource <- Combat.resources() do
    @resource resource
    test "#{resource.code} retains the same combat state through JSON persistence" do
      for outcome <- Combat.outcomes(@resource) do
        resource = Combat.proc(@resource, outcome)
        fortune = Combat.skill("fortunes_end")
        chakra = Combat.skill("chakra_magic")
        battle = Combat.battle([resource], [fortune, chakra])

        Enum.reduce(1..6, {battle, battle}, fn number, {memory, persisted} ->
          action = if rem(number, 2) == 1, do: resource, else: if(rem(number, 4) == 2, do: fortune, else: chakra)
          {skill, item} = Combat.chosen(action)
          seed = {resource.code, outcome, number}
          Combat.seed(seed)
          {memory, _} = Combat.step_in_memory(memory, skill, item)
          Combat.seed(seed)
          {persisted, _} = Combat.step_saved(persisted, skill, item)
          a = List.last(memory.turns)
          b = List.last(persisted.turns)
          assert Map.take(a, [:number, :skill_code, :item_code]) == Map.take(b, [:number, :skill_code, :item_code])
          assert Combat.roundtrip(a.attacker) == b.attacker
          assert Combat.roundtrip(a.defender) == b.defender
          {memory, persisted}
        end)
      end
    end
  end
end
