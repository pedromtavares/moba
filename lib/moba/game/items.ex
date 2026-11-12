defmodule Moba.Game.Items do
  @moduledoc """
  Manages Item records and queries.
  See Moba.Game.Schema.Item for more info.

  Note: a Hero cannot stack speed by having 2 Boots, there is logic here to enforce this.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.{Hero, HeroItem, Item}
  import Ecto.Query
  alias Game.Query.ItemQuery

  @boots ["arcane_boots", "phase_boots", "tranquil_boots", "boots_of_travel", "boots_of_speed"]
  @forge_fee 800

  # -------------------------------- PUBLIC API

  def boots?(%{code: code}), do: code in @boots

  def buy_item!(hero, nil), do: hero

  def buy_item!(hero, item) do
    with_inventory(hero, fn hero ->
      if can_buy_item?(hero, item) do
        inventory = hero.items ++ [item]
        attrs = Map.put(inventory_attributes(hero, inventory), :gold, hero.gold - item_price(item))
        Game.Heroes.update!(hero, attrs, inventory)
      else
        hero
      end
    end)
  end

  def can_equip_item?(hero, item) do
    hero = Repo.preload(hero, :items)

    !has_item?(hero, item)
  end

  def can_buy_item?(hero, item) do
    hero = hero |> Repo.preload(:items) |> preload_forge_pairs()

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

  def item_sell_price(hero, item) do
    case forged_epic(hero, item.code) do
      nil -> item_price(item)
      epic -> item_price(item) + item_price(epic) + @forge_fee
    end
  end

  def forge_available?(hero, legendary) do
    not is_nil(hero.finished_at) && is_nil(hero.archived_at) && legendary?(legendary) && has_item?(hero, legendary)
  end

  def forgeable_epic?(hero, item), do: epic?(item) && !attached_epic?(hero, item.code)

  def forge_price(hero, legendary, epic) do
    previous = forged_epic(hero, legendary.code)
    purchase = if find_item(hero.items, epic.code), do: 0, else: item_price(epic)
    if previous, do: purchase - item_price(previous), else: purchase + @forge_fee
  end

  def forge_item!(player, hero, legendary_code, epic_code) do
    with_inventory(hero, fn current ->
      legendary = find_item(current.items, legendary_code)
      previous = forged_epic(current, legendary_code)

      with true <- current.player_id == player.id,
           %Item{} <- legendary,
           true <- forge_available?(current, legendary),
           %Item{} = epic <- find_item(current.items, epic_code) || current_epic(epic_code),
           true <- forgeable_epic?(current, epic),
           cost when cost <= current.gold <- forge_price(current, legendary, epic) do
        inventory = if previous, do: List.delete(current.items, previous), else: current.items
        inventory = if find_item(inventory, epic.code), do: inventory, else: inventory ++ [epic]
        pairs = Map.put(forge_pairs(current), legendary.code, epic.code)
        updated = update_inventory!(current, inventory, pairs, current.gold - cost)

        {1, _} =
          from(entry in HeroItem,
            join: base in HeroItem,
            on: base.hero_id == entry.hero_id and base.item_id == ^legendary.id,
            where: entry.hero_id == ^current.id and entry.item_id == ^epic.id,
            update: [set: [forged_into_id: base.id]]
          )
          |> Repo.update_all([])

        reload_forge_pairs(updated)
      else
        _ -> current
      end
    end)
  end

  def previous_item_rarity(item) do
    cond do
      rare?(item) -> "normal"
      epic?(item) -> "rare"
      legendary?(item) -> "epic"
    end
  end

  def sell_item!(hero, nil), do: hero

  def sell_item!(hero, item) do
    with_inventory(hero, fn hero ->
      item = Enum.find(hero.items, &(&1.code == item.code))

      if item && !attached_epic?(hero, item.code) do
        gold = hero.gold + item_sell_price(hero, item)

        case forged_epic(hero, item.code) do
          nil ->
            inventory = List.delete(hero.items, item)
            attrs = Map.put(inventory_attributes(hero, inventory), :gold, gold)
            Game.Heroes.update!(hero, attrs, inventory)

          epic ->
            pairs = Map.delete(forge_pairs(hero), item.code)

            hero
            |> update_inventory!(hero.items -- [item, epic], pairs, gold)
            |> reload_forge_pairs()
        end
      else
        hero
      end
    end)
  end

  def shop_list, do: ItemQuery.base_current() |> Repo.all()

  @doc "A Hero can merge weaker items into stronger items at no extra gold cost."
  def transmute_item!(hero, _, nil), do: hero

  def transmute_item!(hero, ingredients, result) do
    with_inventory(hero, fn hero ->
      if can_equip_item?(hero, result) && has_items?(hero, ingredients) && correct_recipe?(ingredients, result) do
        codes = Enum.map(ingredients, & &1.code)
        inventory = Enum.reject(hero.items, &(&1.code in codes)) ++ [result]
        Game.Heroes.update!(hero, inventory_attributes(hero, inventory), inventory)
      else
        hero
      end
    end)
  end

  defp with_inventory(hero, update) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.one!(from h in Hero, where: h.id == ^hero.id, lock: "FOR UPDATE")
        update.(Game.get_hero!(hero.id))
      end)

    Game.broadcast_to_hero(result.id)
    result
  end

  def sort_items(list), do: Enum.sort_by(list, &(!slot_active?(&1)))

  def slot_active?(%{forged_epic: epic} = item), do: item.active || epic.active
  def slot_active?(item), do: item.active

  def preload_forge_pairs(%Hero{finished_at: finished_at} = hero) when not is_nil(finished_at),
    do: Repo.preload(hero, forged_components: :forged_into)

  def preload_forge_pairs(hero), do: hero

  def forge_pairs(%{forged_pairs: pairs}) when is_map(pairs), do: pairs
  def forge_pairs(%{forged_pairs: [legendary, epic]}), do: %{legendary => epic}
  def forge_pairs(%{forged_pairs: []}), do: %{}

  def forge_pairs(%{forged_components: [_ | _] = components, items: items}) do
    codes = Map.new(items, &{&1.id, &1.code})

    for %{forged_into: %{item_id: base_id}, item_id: epic_id} <- components,
        legendary = codes[base_id],
        epic = codes[epic_id],
        into: %{},
        do: {legendary, epic}
  end

  def forge_pairs(_hero), do: %{}

  def item_slots(%{items: items} = hero) do
    pairs = forge_pairs(hero)
    attached = Map.values(pairs)

    for item <- items, item.code not in attached do
      case find_item(items, pairs[item.code]) do
        nil -> item
        epic -> Map.put(item, :forged_epic, epic)
      end
    end
  end

  def slot_items(item) do
    case Map.pop(item, :forged_epic) do
      {nil, item} -> [item]
      {epic, item} -> [item, epic]
    end
  end

  def activation(item) do
    case Enum.filter(slot_items(item), & &1.active) do
      [] ->
        nil

      [first | _] = components ->
        %{
          components: components,
          energy: Enum.sum(Enum.map(components, &(&1.mp_cost || 0))),
          cooldown: Enum.max(Enum.map(components, &(&1.cooldown || 1))),
          cooldown_code: first.code
        }
    end
  end

  def item_priority_codes(hero) do
    bases_by_epic = Map.new(forge_pairs(hero), fn {base, epic} -> {epic, base} end)

    (hero.item_order || [])
    |> Enum.map(&Map.get(bases_by_epic, &1, &1))
    |> Enum.uniq()
  end

  def inventory_items(hero) do
    order = if hero.inventory_order == [], do: item_priority_codes(hero), else: hero.inventory_order
    slots = sort_items(item_slots(hero))
    Enum.map(ordered_codes(order, slots), &find_item(slots, &1))
  end

  def reorder_inventory!(player, hero, codes) when is_list(codes) do
    with_inventory(hero, fn current ->
      slots = item_slots(current)
      owned_codes = Enum.map(slots, & &1.code)

      if current.player_id == player.id && length(codes) == length(owned_codes) &&
           Enum.sort(codes) == Enum.sort(owned_codes) do
        active_codes = Enum.filter(codes, fn code -> slots |> find_item(code) |> slot_active?() end)

        Game.Heroes.update!(current, %{inventory_order: codes, item_order: active_codes})
      else
        current
      end
    end)
  end

  def reorder_inventory!(_player, hero, _codes), do: hero

  # --------------------------------

  defp inventory_attributes(hero, items) do
    inventory = %{hero | items: items}
    slots = item_slots(inventory)

    item_attributes(items)
    |> Map.put(:item_order, ordered_codes(item_priority_codes(inventory), Enum.filter(slots, &slot_active?/1)))
    |> Map.put(
      :inventory_order,
      if(hero.inventory_order == [],
        do: [],
        else: ordered_codes(hero.inventory_order, slots)
      )
    )
  end

  defp update_inventory!(hero, inventory, pairs, gold) do
    attrs =
      hero
      |> Map.put(:item_order, item_priority_codes(hero))
      |> Map.put(:forged_pairs, pairs)
      |> inventory_attributes(inventory)
      |> Map.put(:gold, gold)

    Game.Heroes.update!(hero, attrs, inventory)
  end

  defp reload_forge_pairs(hero), do: Repo.preload(hero, [forged_components: :forged_into], force: true)

  defp current_epic(code) do
    ItemQuery.single_current()
    |> ItemQuery.enabled()
    |> ItemQuery.with_rarities(["epic"])
    |> ItemQuery.with_code(code)
    |> Repo.one()
  end

  defp forged_epic(hero, legendary), do: find_item(hero.items, forge_pairs(hero)[legendary])

  defp attached_epic?(hero, epic), do: epic in Map.values(forge_pairs(hero))

  defp find_item(items, code), do: Enum.find(items, &(&1.code == code))

  defp ordered_codes(order, items) do
    codes = Enum.map(items, & &1.code)
    saved = Enum.filter(order || [], &(&1 in codes)) |> Enum.uniq()
    saved ++ (codes -- saved)
  end

  defp has_item?(hero, item), do: Enum.any?(hero.items, &(&1.code == item.code))

  defp full_inventory?(hero), do: length(item_slots(hero)) >= 6

  defp has_items?(hero, items) do
    Enum.all?(items, fn item -> item && !attached_epic?(hero, item.code) && has_item?(hero, item) end)
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
