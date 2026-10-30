defmodule Moba.Engine.StartingResourcesTest do
  use Moba.DataCase

  alias Moba.Engine.Core.Turns

  test "first-turn resource snapshots preserve partial resources and zero energy" do
    attacker = create_base_hero()
    battle = create_basic_battle(attacker, create_base_hero())
    turn = Turns.build_turn(battle, %{attacker_initial_hp: 123.4, attacker_initial_mp: 0})
    owner = if turn.attacker.hero_id == attacker.id, do: turn.attacker, else: turn.defender

    assert owner.starting_hp == 123
    assert owner.starting_mp == 0
    assert owner.current_hp == 123.4
    assert owner.current_mp == 0
  end

  test "stored snapshots follow each hero across alternating turns" do
    battle = create_basic_battle(create_base_hero(), create_base_hero())
    battle = Engine.auto_finish_battle!(battle) |> then(&Engine.get_battle!(&1.id))

    for {turn, previous} <- Enum.zip(battle.turns, [nil | battle.turns]) do
      for battler <- [turn.attacker, turn.defender] do
        if previous do
          before = if previous.attacker.hero_id == battler.hero_id, do: previous.attacker, else: previous.defender
          assert battler.starting_hp == round(before.current_hp)
          assert battler.starting_mp == round(before.current_mp)
        else
          assert battler.starting_hp == battler.total_hp
          assert battler.starting_mp == battler.total_mp
        end
      end
    end
  end
end
