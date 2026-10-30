defmodule MobaWeb.V2.BattleResourceTest do
  use ExUnit.Case, async: true

  alias MobaWeb.V2.Components.BattleComponents

  test "damage and recovery occupy their actual proportion of the total" do
    loss = BattleComponents.resource_segments(80, 30, 100)
    assert loss.change == -50
    assert loss.retained_percentage == 30
    assert loss.change_percentage == 50

    gain = BattleComponents.resource_segments(30, 80, 100)
    assert gain.change == 50
    assert gain.retained_percentage == 30
    assert gain.change_percentage == 50

    tiny = BattleComponents.resource_segments(1000, 999, 1000)
    assert_in_delta tiny.change_percentage, 0.1, 0.00001
  end

  test "overkill, overhealing and invalid totals never inflate the visible change" do
    dead = BattleComponents.resource_segments(60, -40, 100)
    assert dead.current == 0
    assert dead.change == -60
    assert dead.change_percentage == 60

    capped = BattleComponents.resource_segments(90, 140, 100)
    assert capped.current == 100
    assert capped.change == 10
    assert capped.change_percentage == 10

    assert BattleComponents.resource_segments(100, 130, 100).change == 0
    assert BattleComponents.resource_segments(nil, 30, 100).change == 0

    for total <- [0, -1] do
      empty = BattleComponents.resource_segments(10, -10, total)
      assert empty.current == 0
      assert empty.change == 0
      assert empty.retained_percentage == 0
      assert empty.change_percentage == 0
    end
  end

  test "all bounded segments fit the gauge and end at the previous or current resource" do
    for total <- [0, 1, 10, 100], previous <- -10..110//5, current <- -10..110//5 do
      bar = BattleComponents.resource_segments(previous, current, total)
      assert bar.retained_percentage >= 0
      assert bar.change_percentage >= 0
      assert bar.retained_percentage + bar.change_percentage <= 100
      assert bar.current >= 0 && bar.current <= total
      assert bar.previous >= 0 && bar.previous <= total
      assert bar.change == bar.current - bar.previous
    end
  end
end
