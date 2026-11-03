defmodule MobaWeb.V2.SkillUpgradeTooltipTest do
  use Moba.DataCase

  alias Moba.Game
  alias MobaWeb.V2.Components.TooltipComponents, as: TT

  test "upgrade preview has one skill heading and only changed metadata" do
    current = Game.get_current_skill!("blink_strike", 2)
    next = Game.get_current_skill!("blink_strike", 3)
    document = TT.skill_upgrade_tooltip(current, next) |> LazyHTML.from_fragment()

    assert LazyHTML.query(document, "h3") |> LazyHTML.text() == "Blink Strike"
    assert LazyHTML.query(document, ".skill-upgrade-preview header") |> LazyHTML.text() =~ "Next level"
    assert LazyHTML.query(document, ".skill-upgrade-preview header strong") |> LazyHTML.text() == "Lv 3"
    assert LazyHTML.query(document, ".skill-upgrade-meta") |> LazyHTML.text() == to_string(next.mp_cost)
    assert Enum.count(LazyHTML.query(document, ".skill-upgrade-meta .ui-clock")) == 0
    assert Enum.count(LazyHTML.query(document, ".skill-upgrade-meta .ui-burst")) == 0
    assert LazyHTML.query(document, ".skill-upgrade-effects") |> LazyHTML.text() =~ "Damage:"
    assert Enum.count(LazyHTML.query(document, "hr")) == 0
  end

  test "changed cooldown and damage type remain visible in the upgrade preview" do
    current = Game.get_current_skill!("blink_strike", 2)
    next = %{Game.get_current_skill!("blink_strike", 3) | cooldown: current.cooldown + 1, damage_type: "magic"}
    document = TT.skill_upgrade_tooltip(current, next) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, ".skill-upgrade-meta .ui-clock")) == 1
    assert LazyHTML.query(document, ".skill-upgrade-meta") |> LazyHTML.text() =~ "Magic Damage"
  end
end
