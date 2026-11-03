defmodule Moba.Game.SkillDescriptionsTest do
  use ExUnit.Case, async: true

  alias Moba.Game.{SkillDescriptions, Schema.Skill}
  alias MobaWeb.V2.Components.TooltipComponents, as: Tooltip

  @catalog File.read!(Path.expand("../../../priv/repo/seed_catalog.json", __DIR__))
           |> Jason.decode!()
           |> Map.fetch!("skills")

  defp rank(attrs), do: struct(Skill, Map.new(attrs, fn {key, value} -> {String.to_existing_atom(key), value} end))
  defp skill(code, level), do: @catalog |> Enum.find(&(&1["code"] == code && &1["level"] == level)) |> rank()

  test "all seeded ranks have authored, reproducible descriptions and render without legacy tags" do
    assert @catalog != []

    for attrs <- @catalog do
      resource = rank(attrs)
      content = SkillDescriptions.describe(resource)
      assert content.authored, "Missing authored copy for #{resource.code} rank #{resource.level}"
      assert content.summary != ""
      assert length(String.split(content.summary)) <= 16
      assert length(content.notes) <= 1
      for note <- content.notes, do: assert(length(String.split(note)) <= 12)
      assert attrs["description"] == content.summary
      assert attrs["effects"] == SkillDescriptions.plain_effects(resource)
      html = Tooltip.skill_tooltip(resource)
      document = LazyHTML.from_fragment(html)
      assert Enum.count(LazyHTML.query(document, ".skill-tooltip")) == 1

      assert Enum.count(
               LazyHTML.query(document, ".skill-tooltip-effects dt .skill-tooltip-effect-icon[aria-hidden=true]")
             ) == length(content.effects)

      refute LazyHTML.text(document) =~ ~r/\[(?:hp|damage|status|armor|base_damage|atk_multiplier)\]/
      for row <- content.effects, term <- row.value, do: assert(is_number(term.amount))
    end
  end

  test "published rank values are used directly instead of freezing seed balance values" do
    resource = %{skill("blink_strike", 2) | base_damage: 999, mp_cost: 1}
    document = Tooltip.skill_tooltip(resource) |> LazyHTML.from_fragment()
    assert LazyHTML.query(document, "[data-effect=first] dd") |> LazyHTML.text() =~ "999"
    assert LazyHTML.query(document, ".skill-tooltip-meta") |> LazyHTML.text() =~ "1 Energy"
  end

  test "charging, stacking and defensive skills retain their essential rules" do
    echo = SkillDescriptions.describe(skill("echo_stomp", 3))
    assert Enum.join(echo.notes) =~ "Ignores Evade"
    assert Enum.any?(echo.effects, &(&1.key == :interrupted))
    assert SkillDescriptions.summary(skill("fiery_soul", 1)) =~ "rest of the battle"
    assert SkillDescriptions.summary(skill("borrowed_time", 1)) =~ "next enemy attack"

    for resource <- [Moba.Game.basic_attack(), Moba.Game.evade()] do
      assert SkillDescriptions.describe(resource).authored
      assert Tooltip.skill_tooltip(resource) != ""
    end
  end

  test "cleanse limits and interruption damage follow the engine's rank fields" do
    for level <- 1..5 do
      cleanse =
        skill("chakra_magic", level)
        |> SkillDescriptions.describe()
        |> Map.fetch!(:effects)
        |> Enum.find(&(&1.key == :cleanse))

      assert hd(cleanse.value).amount == level
    end

    drain = skill("life_drain", 1)
    interruption = SkillDescriptions.describe(drain).effects |> Enum.find(&(&1.key == :interrupted))
    assert hd(interruption.value).amount == drain.extra_amount
    refute SkillDescriptions.summary(drain) =~ "double"
    execute = SkillDescriptions.describe(skill("culling_blade", 1)).effects |> Enum.find(&(&1.key == :threshold))
    assert hd(execute.value).amount == 35.0

    for {level, expected} <- [{1, 35}, {2, 40}, {3, 45}] do
      threshold =
        SkillDescriptions.describe(skill("culling_blade", level)).effects |> Enum.find(&(&1.key == :threshold))

      assert hd(threshold.value).amount == expected
    end
  end

  test "a passive's zero cooldown is shown explicitly at its final rank" do
    document = skill("phase_shift", 5) |> Tooltip.skill_tooltip() |> LazyHTML.from_fragment()
    assert LazyHTML.query(document, ".skill-tooltip-meta") |> LazyHTML.text() =~ "No cooldown"
  end

  test "metadata uses coloured energy, cooldown and damage icons without list markers" do
    document = skill("walrus_punch", 1) |> Tooltip.skill_tooltip() |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, ".skill-tooltip-meta [data-kind=energy] .ui-bolt")) == 1
    assert Enum.count(LazyHTML.query(document, ".skill-tooltip-meta [data-kind=cooldown] .ui-clock")) == 1
    assert Enum.count(LazyHTML.query(document, ".skill-tooltip-meta [data-kind=normal] .ui-burst")) == 1
    assert Enum.count(LazyHTML.query(document, ".skill-tooltip-notes li")) == 0
  end

  test "percentage signs share the coloured number with a space before stat names" do
    document = skill("blink_strike", 2) |> Tooltip.skill_tooltip() |> LazyHTML.from_fragment()
    assert LazyHTML.query(document, "[data-effect=first] .is-percentage strong") |> LazyHTML.text() == "110%"

    assert LazyHTML.query(document, "[data-effect=first] .is-percentage .skill-tooltip-unit") |> LazyHTML.text() ==
             " Attack"

    assert LazyHTML.query(document, "[data-effect=first] .is-percentage") |> LazyHTML.text() =~ "110% Attack"
  end

  test "effect rows and next-rank changes use matching semantic icons" do
    for {code, key, icon} <- [
          {"death_pulse", "damage", "ui-burst"},
          {"death_pulse", "healing", "ui-heart"},
          {"empower", "power", "ui-vortex"},
          {"empower", "duration", "ui-clock"},
          {"chakra_magic", "energy", "ui-bolt"},
          {"chakra_magic", "cleanse", "ui-refresh"},
          {"blade_fury", "armor", "ui-shield"},
          {"coup", "chance", "ui-dice"},
          {"walrus_punch", "stun", "ui-star"},
          {"psionic_trap", "attack", "ui-dagger"}
        ] do
      document = Tooltip.skill_upgrade_tooltip(skill(code, 1), skill(code, 2)) |> LazyHTML.from_fragment()
      assert Enum.count(LazyHTML.query(document, "[data-effect=#{key}] dt .#{icon}")) == 1

      for row <- LazyHTML.query(document, "[data-change]") do
        assert Enum.count(LazyHTML.query(row, "dt .skill-tooltip-effect-icon")) == 1
      end
    end
  end

  test "unknown skill copy is escaped and does not become executable markup" do
    resource = %Skill{code: "custom", name: "<img src=x>", description: "<script>alert(1)</script>"}
    document = Tooltip.skill_tooltip(resource) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, "script")) == 0
    assert LazyHTML.query(document, "h3") |> LazyHTML.text() == "<img src=x>"
  end
end
