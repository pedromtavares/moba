defmodule Moba.Game.Items do
  @moduledoc """
  Manages Item records and queries.
  See Moba.Game.Schema.Item for more info.

  Note: a Hero cannot stack speed by having 2 Boots, there is logic here to enforce this.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Item
  alias Game.Query.ItemQuery

  @boots ["arcane_boots", "phase_boots", "tranquil_boots", "boots_of_travel", "boots_of_speed"]

  # -------------------------------- PUBLIC API

  def buy_item!(hero, nil), do: hero

  def buy_item!(hero, item) do
    hero = Repo.preload(hero, :items)

    if can_buy_item?(hero, item) do
      hero
      |> equip(item)
      |> Game.update_hero!(%{
        gold: hero.gold - item_price(item)
      })
    else
      hero
    end
  end

  def can_equip_item?(hero, item) do
    hero = Repo.preload(hero, :items)

    !has_item?(hero, item)
  end

  def can_buy_item?(hero, item) do
    hero = Repo.preload(hero, :items)

    !full_inventory?(hero) && can_equip_item?(hero, item) && hero.gold >= item_price(item)
  end

  def get_item!(id) when id == "", do: nil
  def get_item!(id), do: Repo.get!(Item, id)

  def get_item_by_code!(code) when code == "", do: nil
  def get_item_by_code!(code), do: Repo.get_by!(ItemQuery.single_current(), code: code)

  def item_attributes(items) do
    %{
      item_hp: attribute_sum(items, :base_hp),
      item_mp: attribute_sum(items, :base_mp),
      item_atk: attribute_sum(items, :base_atk),
      item_speed: speed_sum(items),
      item_power: attribute_sum(items, :base_power),
      item_armor: attribute_sum(items, :base_armor),
      item_order: items_to_order(items)
    }
  end

  def item_ingredients_count(item) do
    cond do
      rare?(item) -> 3
      epic?(item) -> 2
      legendary?(item) -> 2
      true -> 0
    end
  end

  def item_price(item) do
    cond do
      normal?(item) -> Moba.normal_items_price()
      rare?(item) -> Moba.rare_items_price()
      epic?(item) -> Moba.epic_items_price()
      legendary?(item) -> Moba.legendary_items_price()
      true -> 0
    end
  end

  def item_sell_price(%{finished_at: finished}, item) when not is_nil(finished), do: item_price(item)
  def item_sell_price(_, item), do: trunc(item_price(item) * 0.9)

  def previous_item_rarity(item) do
    cond do
      rare?(item) -> "normal"
      epic?(item) -> "rare"
      legendary?(item) -> "epic"
    end
  end

  def sell_item!(hero, nil), do: hero

  def sell_item!(hero, item) do
    hero = Repo.preload(hero, :items)

    if has_item?(hero, item) do
      hero
      |> unequip([item])
      |> Game.update_hero!(%{
        gold: hero.gold + item_sell_price(hero, item)
      })
    else
      hero
    end
  end

  def shop_list, do: ItemQuery.base_current() |> Repo.all()

  @doc """
  A Hero can transform weaker items into stronger items by merging them at no extra gold cost
  """
  def transmute_item!(hero, _, nil), do: hero

  def transmute_item!(hero, ingredients, result) do
    hero = Repo.preload(hero, :items)

    if can_equip_item?(hero, result) && has_items?(hero, ingredients) && correct_recipe?(ingredients, result) do
      hero
      |> unequip(ingredients)
      |> equip(result)
    else
      hero
    end
  end

  def sort_items(list), do: Enum.sort_by(list, fn item -> !item.active end)

  # --------------------------------

  defp has_item?(hero, item), do: Enum.map(hero.items, & &1.code) |> Enum.member?(item.code)

  defp full_inventory?(hero), do: length(hero.items) >= 6

  defp has_items?(hero, items), do: Enum.all?(items, fn item -> has_item?(hero, item) end)

  defp equip(hero, item) do
    new_inventory = hero.items ++ [item]

    Game.update_hero!(
      hero,
      item_attributes(new_inventory),
      new_inventory
    )
  end

  defp unequip(hero, items) do
    items_codes = Enum.map(items, & &1.code)
    new_inventory = Enum.filter(hero.items, fn item -> !Enum.member?(items_codes, item.code) end)

    Game.update_hero!(
      hero,
      item_attributes(new_inventory),
      new_inventory
    )
  end

  defp correct_recipe?(ingredients, result) do
    ingredients = Enum.uniq(ingredients)

    length(ingredients) == item_ingredients_count(result) &&
      cond do
        rare?(result) -> Enum.all?(ingredients, fn item -> normal?(item) end)
        epic?(result) -> Enum.all?(ingredients, fn item -> rare?(item) end)
        legendary?(result) -> Enum.all?(ingredients, fn item -> epic?(item) end)
        true -> false
      end
  end

  defp attribute_sum(items, attribute) do
    Enum.reduce(items, 0, fn item, acc -> if item, do: acc + Map.get(item, attribute), else: acc + 0 end)
  end

  defp speed_sum(items) do
    items
    |> single_boots_collection()
    |> attribute_sum(:base_speed)
  end

  # makes sure only a single boots is used when calculating Speed
  defp single_boots_collection(items) when length(items) > 0 do
    no_boots = Enum.filter(items, fn item -> !Enum.member?(@boots, item.code) end)
    first_boots = (items -- no_boots) |> List.first()
    no_boots ++ [first_boots]
  end

  defp single_boots_collection(items), do: items

  defp items_to_order(items), do: Enum.filter(items, & &1.active) |> Enum.map(& &1.code)

  defp normal?(item), do: item.rarity == "normal"

  defp rare?(item), do: item.rarity == "rare"

  defp epic?(item), do: item.rarity == "epic"

  defp legendary?(item), do: item.rarity == "legendary"
end
