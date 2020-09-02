defmodule MobaWeb.ShopView do
  use MobaWeb, :view

  alias Moba.Game

  def normals(items), do: rarity_filter(items, "normal")
  def rares(items), do: rarity_filter(items, "rare")
  def epics(items), do: rarity_filter(items, "epic")
  def legendaries(items), do: rarity_filter(items, "legendary")

  def transmute_instructions_for(item) do
    count = Game.item_ingredients_count(item)
    rarity = Game.previous_rarity_item(item)
    "Choose #{count} #{String.capitalize(rarity)} items"
  end

  def can_select_inventory(_, nil, _), do: true

  def can_select_inventory(item, transmute, recipe) do
    !Enum.member?(recipe, item) && item.rarity == Game.previous_rarity_item(transmute)
  end

  def proper_recipe(recipe, transmute) do
    length(recipe) == Game.item_ingredients_count(transmute)
  end

  def normal?(item), do: item.rarity == "normal"

  def can_transmute?(hero, item), do: can_equip?(hero, item) && length(hero.items) >= ingredients_count_for(item)

  def can_buy?(hero, item), do: Game.can_buy_item?(hero, item)

  def can_equip?(hero, item), do: Game.can_equip_item?(hero, item)

  def price(item), do: Game.item_price(item)

  def sell_price(item), do: Game.item_sell_price(item)

  def ingredients_count_for(item), do: Game.item_ingredients_count(item)

  def update_recipe(item, current_recipe, current_transmute) do
    rarity = Game.previous_rarity_item(current_transmute)

    updated =
      if item.rarity == rarity do
        [item | current_recipe]
      else
        current_recipe
      end

    Enum.take(updated, ingredients_count_for(current_transmute))
  end

  defp rarity_filter(items, rarity), do: Enum.filter(items, fn item -> item.rarity == rarity end)
end
