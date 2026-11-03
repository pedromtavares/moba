defmodule MobaWeb.V2.ShopComponent do
  use MobaWeb, :v2_live_component

  import MobaWeb.V2.Components.HeroBarComponents
  alias MobaWeb.V2.TutorialComponent

  embed_templates "shop_component/*"

  def mount(socket) do
    {:ok,
     assign(socket,
       items: [],
       transmute: nil,
       selected_category: "normal",
       detail_tab: "overview",
       item_inspected: false,
       selected_shop: nil,
       recipe: [],
       selected_inventory: nil
     )}
  end

  def update(%{current_hero: hero, tutorial_step: step} = assigns, socket) do
    previous = socket.assigns[:current_hero]
    hero_changed? = is_nil(previous) || previous.id != hero.id || inventory_ids(previous) != inventory_ids(hero)

    socket =
      socket
      |> assign(
        items: Moba.cached_items(),
        current_hero: hero,
        tutorial_step: step,
        current_player: hero.player,
        reorderable: Map.get(assigns, :reorderable, false),
        event_target: Map.get(assigns, :event_target)
      )
      |> reset_selection_if_hero_changed(hero_changed?)

    {:ok, socket}
  end

  def handle_event("select-shop", %{"code" => code}, socket) do
    case get_item(code, socket) do
      nil ->
        {:noreply, socket}

      item ->
        {:noreply,
         assign(socket,
           selected_shop: item,
           item_inspected: true,
           selected_inventory: nil,
           selected_category: item.rarity,
           transmute: nil,
           recipe: []
         )}
    end
  end

  def handle_event("inspect-tab", %{"tab" => tab}, socket) when tab in ["overview", "effects"] do
    {:noreply, assign(socket, detail_tab: tab)}
  end

  def handle_event("select-category", %{"rarity" => rarity}, socket)
      when rarity in ["normal", "rare", "epic", "legendary", "inventory"] do
    if rarity == "inventory" do
      {:noreply,
       assign(socket,
         selected_category: rarity,
         selected_inventory: List.first(Game.inventory_items(socket.assigns.current_hero)),
         selected_shop: nil,
         transmute: nil,
         recipe: []
       )}
    else
      item = socket.assigns.items |> rarity_filter(rarity) |> List.first()

      {:noreply,
       assign(socket,
         selected_category: rarity,
         selected_shop: item,
         selected_inventory: nil,
         transmute: nil,
         recipe: []
       )}
    end
  end

  def handle_event("select-inventory", %{"code" => code}, %{assigns: %{transmute: nil}} = socket) do
    item = Enum.find(socket.assigns.current_hero.items, &(&1.code == code))

    {:noreply, assign(socket, selected_inventory: item, selected_shop: nil, selected_category: "inventory")}
  end

  def handle_event("select-inventory", %{"code" => code}, %{assigns: assigns} = socket) do
    item = Enum.find(assigns.current_hero.items, &(&1.code == code))

    updated = update_item_recipe(item, assigns.recipe, assigns.transmute)

    {:noreply, assign(socket, recipe: updated)}
  end

  def handle_event("start-transmute", _, %{assigns: %{selected_shop: nil}} = socket), do: {:noreply, socket}

  def handle_event("start-transmute", _, %{assigns: assigns} = socket) do
    {:noreply,
     socket
     |> assign(
       transmute: assigns.selected_shop,
       selected_shop: nil,
       selected_inventory: nil,
       selected_category: "inventory",
       recipe: []
     )
     |> TutorialComponent.next_step(8)}
  end

  def handle_event("cancel-transmute", _, %{assigns: %{transmute: nil}} = socket), do: {:noreply, socket}

  def handle_event("cancel-transmute", _, socket) do
    item = socket.assigns.transmute
    {:noreply, assign(socket, transmute: nil, recipe: [], selected_shop: item, selected_category: item.rarity)}
  end

  def render(assigns) do
    item = assigns.transmute || assigns.selected_shop || assigns.selected_inventory
    assigns = assign(assigns, detail_item: item, detail_info: item && GH.item_info(item))
    shop(assigns)
  end

  defp get_item(code, socket) do
    Enum.find(socket.assigns.items, fn item -> item.code == code end)
  end

  defp inventory_ids(hero), do: hero.items |> Enum.map(& &1.id) |> Enum.sort()

  defp update_item_recipe(item, current_recipe, current_transmute) do
    rarity = Game.previous_item_rarity(current_transmute)

    updated =
      if item && item.rarity == rarity && item not in current_recipe do
        [item | current_recipe]
      else
        current_recipe
      end

    Enum.take(updated, Game.item_ingredients_count(current_transmute))
  end

  defp categories, do: ["normal", "rare", "epic", "legendary"]

  defp category_price("normal"), do: Moba.normal_items_price()
  defp category_price("rare"), do: Moba.rare_items_price()
  defp category_price("epic"), do: Moba.epic_items_price()
  defp category_price("legendary"), do: Moba.legendary_items_price()

  defp stat_label(:hp), do: {"Health", "heart"}
  defp stat_label(:mp), do: {"Energy", "bolt"}
  defp stat_label(:atk), do: {"Attack", "dagger"}
  defp stat_label(:power), do: {"Power", "vortex"}
  defp stat_label(:armor), do: {"Armor", "shield"}
  defp stat_label(:speed), do: {"Speed", "runner"}

  defp purchase_hint(hero, item) do
    cond do
      !can_equip?(hero, item) -> nil
      length(hero.items) >= 6 -> "Inventory full · sell or transmute an item"
      hero.gold < price(item) -> "#{price(item) - hero.gold} more gold needed"
      true -> nil
    end
  end

  defp transmute_instructions_for(item) do
    count = Game.item_ingredients_count(item)
    rarity = Game.previous_item_rarity(item)
    "Choose #{count} #{String.capitalize(rarity)} items"
  end

  defp can_select_inventory(_, nil, _), do: true

  defp can_select_inventory(item, transmute, recipe) do
    !Enum.member?(recipe, item) && item.rarity == Game.previous_item_rarity(transmute)
  end

  defp proper_recipe(recipe, transmute) do
    length(recipe) == Game.item_ingredients_count(transmute)
  end

  defp can_transmute?(hero, item) do
    can_equip?(hero, item) &&
      Enum.count(hero.items, &(&1.rarity == Game.previous_item_rarity(item))) >= ingredients_count_for(item)
  end

  defp can_buy?(hero, item), do: Game.can_buy_item?(hero, item)

  defp can_equip?(hero, item), do: Game.can_equip_item?(hero, item)

  defp price(item), do: Game.item_price(item)

  defp sell_price(hero, item), do: Game.item_sell_price(hero, item)

  defp ingredients_count_for(item), do: Game.item_ingredients_count(item)

  defp rarity_filter(items, rarity) do
    items
    |> Enum.filter(&(&1.rarity == rarity))
    |> Enum.sort_by(&shop_item_priority/1)
  end

  defp shop_item_priority(%{rarity: "normal", code: "boots_of_speed"}), do: 0
  defp shop_item_priority(%{rarity: "normal", code: "sages_mask"}), do: 1
  defp shop_item_priority(%{rarity: "rare", code: "tranquil_boots"}), do: 0
  defp shop_item_priority(%{rarity: "rare", code: "arcane_boots"}), do: 1

  defp shop_item_priority(%{rarity: rarity, code: code}) when rarity in ["epic", "legendary"],
    do: if(String.contains?(code, "boots"), do: 0, else: 2)

  defp shop_item_priority(_), do: 2

  defp reset_selection_if_hero_changed(socket, true) do
    item =
      socket.assigns.transmute || socket.assigns.selected_shop ||
        List.first(rarity_filter(socket.assigns.items, "normal"))

    inventory = socket.assigns.selected_inventory
    inventory = inventory && Enum.find(socket.assigns.current_hero.items, &(&1.code == inventory.code))

    assign(socket,
      selected_shop: if(inventory, do: nil, else: item),
      selected_inventory: inventory,
      selected_category: if(inventory, do: "inventory", else: item.rarity),
      transmute: nil,
      recipe: []
    )
  end

  defp reset_selection_if_hero_changed(socket, false), do: socket
end
