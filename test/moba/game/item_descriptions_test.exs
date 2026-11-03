defmodule Moba.Game.ItemDescriptionsTest do
  use ExUnit.Case, async: true

  alias Moba.Game.{ItemDescriptions, Schema.Item}
  alias MobaWeb.V2.Components.TooltipComponents, as: Tooltip

  @items File.read!(Path.expand("../../../priv/repo/seed_catalog.json", __DIR__))
         |> Jason.decode!()
         |> Map.fetch!("items")

  defp item(code) do
    attrs = Enum.find(@items, &(&1["code"] == code))
    struct(Item, Map.new(attrs, fn {key, value} -> {String.to_existing_atom(key), value} end))
  end

  test "every catalogue item has concise authored copy and an icon for every numeric effect" do
    for attrs <- @items do
      resource = item(attrs["code"])
      content = ItemDescriptions.describe(resource)
      assert content.authored, "Missing copy for #{resource.code}"
      assert length(String.split(content.summary || "")) <= 16
      assert length(content.notes) <= 1
      document = Tooltip.item_tooltip(resource) |> LazyHTML.from_fragment()
      assert Enum.count(LazyHTML.query(document, ".item-tooltip[data-rarity='#{resource.rarity}']")) == 1

      assert Enum.count(LazyHTML.query(document, ".skill-tooltip-effects dt .skill-tooltip-effect-icon")) ==
               length(content.effects)

      for row <- content.effects, value <- row.value, do: assert(is_number(value.amount))
      refute LazyHTML.text(document) =~ ~r/\[(?:hp|mp|damage|status|armor|base_amount)\]/
    end
  end

  test "existing records get the new copy without rewriting their stored descriptions" do
    resource = %{
      item("bloodstone")
      | description: "Old database copy",
        effects: "[hp]Old markup[/hp]",
        hp_regen_multiplier: 0.65,
        base_hp: 99
    }

    document = Tooltip.item_tooltip(resource) |> LazyHTML.from_fragment()
    refute LazyHTML.text(document) =~ "Old"
    assert LazyHTML.query(document, "[data-effect=healing] strong") |> LazyHTML.text() == "65%"
    assert LazyHTML.query(document, "[data-stat=base_hp] dd") |> LazyHTML.text() == "+99"
    assert Enum.count(LazyHTML.query(document, "[data-effect=healing] .ui-heart")) == 1

    assert LazyHTML.query(document, "[data-effect=healing] .skill-tooltip-term") |> LazyHTML.text() =~
             "65% enemy healing"
  end

  test "equipment stats have matching icons and active items retain their full cost and cooldown labels" do
    document = Tooltip.item_tooltip(item("shivas_guard")) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, "[data-stat=base_armor] .ui-shield")) == 1
    assert Enum.count(LazyHTML.query(document, "[data-stat=base_mp] .ui-bolt")) == 1
    assert Enum.count(LazyHTML.query(document, "[data-effect=damage] .ui-burst")) == 1

    assert LazyHTML.query(document, ".skill-tooltip-meta [data-kind=energy]") |> LazyHTML.text() |> String.trim() ==
             "5 Energy"

    assert LazyHTML.query(document, ".skill-tooltip-meta [data-kind=cooldown]") |> LazyHTML.text() |> String.trim() ==
             "4 turns"

    passive = Tooltip.item_tooltip(item("linkens_sphere")) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(passive, ".skill-tooltip-meta [data-kind=energy]")) == 0

    assert LazyHTML.query(passive, ".skill-tooltip-meta [data-kind=cooldown]") |> LazyHTML.text() |> String.trim() ==
             "4 turns"
  end

  test "unknown item names and descriptions remain escaped" do
    resource = %Item{
      code: "custom_item",
      name: "<script>bad()</script>",
      description: "<img src=x onerror=bad()>",
      rarity: "rare"
    }

    document = Tooltip.item_tooltip(resource) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, "script, img")) == 0
    assert LazyHTML.query(document, "h3") |> LazyHTML.text() == resource.name
    assert LazyHTML.query(document, ".skill-tooltip-summary") |> LazyHTML.text() == resource.description
  end
end
