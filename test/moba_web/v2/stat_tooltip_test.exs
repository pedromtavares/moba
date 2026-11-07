defmodule MobaWeb.V2.StatTooltipTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MobaWeb.V2.Components.GameComponents

  @hero %{
    total_hp: 285,
    item_hp: 35,
    total_mp: 45,
    item_mp: 10,
    atk: 26,
    item_atk: 5,
    power: 10,
    item_power: 0,
    armor: 5,
    item_armor: -2,
    speed: 100,
    item_speed: 10,
    avatar: %{hp_per_level: 30, mp_per_level: 3, atk_per_level: 2}
  }

  test "the hero bar renders colored stat cards with the full value breakdown" do
    tooltips =
      render_component(&GameComponents.hero_stat_group/1, hero: @hero, variant: "hero_bar", tooltip_mode: "detailed")
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-toggle=tooltip]")
      |> LazyHTML.attribute("title")
      |> Enum.map(&LazyHTML.from_fragment/1)

    for {tooltip, {name, tone, total, base, items, growth}} <-
          Enum.zip(tooltips, [
            {"Health", "damage", "320", "285", "+35", "+30"},
            {"Energy", "energy", "55", "45", "+10", "+3"},
            {"Attack", "attack", "31", "26", "+5", "+2"},
            {"Power", "power", "10", "10", "0", ""},
            {"Armor", "armor", "3", "5", "-2", ""},
            {"Speed", "speed", "110", "100", "+10", ""}
          ]) do
      assert text(tooltip, ".stat-tooltip[data-tone=#{tone}] h3") == name
      assert text(tooltip, ".stat-tooltip-total") =~ total
      assert text(tooltip, "[data-stat-source=base] dd") == base
      assert text(tooltip, "[data-stat-source=items] dd") == items
      assert text(tooltip, "[data-stat-source=growth] dd") == growth
    end

    assert length(tooltips) == 6
  end

  test "compact readouts still use plain stat names" do
    labels =
      render_component(&GameComponents.hero_stat_group/1, hero: @hero)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-toggle=tooltip]")
      |> LazyHTML.attribute("title")

    assert labels == ~w(Health Energy Attack Power Armor Speed)
  end

  defp text(document, selector), do: document |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()
end
