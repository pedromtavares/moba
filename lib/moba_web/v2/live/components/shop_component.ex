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
       selected_shop: nil,
       recipe: [],
       selected_inventory: nil
     )}
  end

  def update(%{current_hero: hero, tutorial_step: step} = assigns, socket) do
    hero_changed? = socket.assigns[:current_hero] != hero

    socket =
      socket
      |> assign(
        items: Moba.cached_items(),
        current_hero: hero,
        tutorial_step: step,
        current_player: hero.player,
        event_target: Map.get(assigns, :event_target)
      )
      |> reset_selection_if_hero_changed(hero_changed?)

    {:ok, socket}
  end

  def handle_event("select-shop", %{"code" => code}, socket) do
    item = get_item(code, socket)

    {:noreply, assign(socket, selected_shop: item, selected_inventory: nil)}
  end

  def handle_event("select-inventory", %{"code" => code}, %{assigns: %{transmute: nil}} = socket) do
    item = get_item(code, socket)

    {:noreply, assign(socket, selected_inventory: item, selected_shop: nil)}
  end

  def handle_event("select-inventory", %{"code" => code}, %{assigns: assigns} = socket) do
    item = get_item(code, socket)

    updated = update_item_recipe(item, assigns.recipe, assigns.transmute)

    {:noreply, assign(socket, recipe: updated)}
  end

  def handle_event("start-transmute", _, %{assigns: assigns} = socket) do
    {:noreply,
     socket
     |> assign(transmute: assigns.selected_shop, selected_shop: nil, selected_inventory: nil, recipe: [])
     |> TutorialComponent.next_step(8)}
  end

  def handle_event("cancel-transmute", _, socket) do
    {:noreply, assign(socket, transmute: nil)}
  end

  def render(assigns) do
    shop(assigns)
  end

  attr :item, :map, required: true

  defp shop_item(assigns) do
    ~H"""
    <div class="col-4 col-md-4 mb-2 d-flex justify-content-center">
      <img
        src={GH.image_url(@item)}
        data-toggle="tooltip"
        title={GH.item_description(@item)}
        class={"item-img code-#{@item.code} tooltip-mobile #{if @item.active, do: "active"}"}
        phx-click="select-shop"
        phx-value-code={@item.code}
        phx-target="#shop"
        id={"item-#{@item.id}"}
      />
    </div>
    """
  end

  attr :hero, :map, required: true
  attr :selected_shop, :map, required: true
  attr :event_target, :any, default: nil

  defp shop_actions(assigns) do
    ~H"""
    <hr class="img-border-xs" />
    <div class="row selected-shop">
      <div class="col d-flex justify-content-center">
        <img
          src={GH.image_url(@selected_shop)}
          data-toggle="tooltip"
          title={GH.item_description(@selected_shop)}
          class="item-img"
        />
      </div>
    </div>
    <hr />
    <div class="row">
      <div class="col center">
        <button
          class="btn btn-warning buy-button"
          phx-click="buy"
          phx-value-code={@selected_shop.code}
          disabled={!can_buy?(@hero, @selected_shop)}
          phx-hook="Loading"
          loading="Buying..."
          id="buy-button"
          {target_attrs(@event_target)}
        >
          <span class="loading-text">Buy for <i class="fa fa-coins"></i> {price(@selected_shop)}</span>
        </button>
        <%= unless normal?(@selected_shop) do %>
          <button
            class="btn btn-primary transmute-button"
            phx-click="start-transmute"
            phx-target="#shop"
            disabled={!can_transmute?(@hero, @selected_shop)}
          >
            <i class="fa fa-refresh"></i> Transmute
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp get_item(code, socket) do
    Enum.find(socket.assigns.items, fn item -> item.code == code end)
  end

  defp update_item_recipe(item, current_recipe, current_transmute) do
    rarity = Game.previous_item_rarity(current_transmute)

    updated =
      if item.rarity == rarity do
        [item | current_recipe]
      else
        current_recipe
      end

    Enum.take(updated, Game.item_ingredients_count(current_transmute))
  end

  defp normals(items), do: rarity_filter(items, "normal")
  defp rares(items), do: rarity_filter(items, "rare")
  defp epics(items), do: rarity_filter(items, "epic")
  defp legendaries(items), do: rarity_filter(items, "legendary")

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

  defp normal?(item), do: item.rarity == "normal"

  defp can_transmute?(hero, item), do: can_equip?(hero, item) && length(hero.items) >= ingredients_count_for(item)

  defp can_buy?(hero, item), do: Game.can_buy_item?(hero, item)

  defp can_equip?(hero, item), do: Game.can_equip_item?(hero, item)

  defp price(item), do: Game.item_price(item)

  defp sell_price(hero, item), do: Game.item_sell_price(hero, item)

  defp ingredients_count_for(item), do: Game.item_ingredients_count(item)

  defp rarity_filter(items, rarity), do: Enum.filter(items, fn item -> item.rarity == rarity end)

  defp reset_selection_if_hero_changed(socket, true) do
    assign(socket, selected_shop: nil, selected_inventory: nil, transmute: nil, recipe: [])
  end

  defp reset_selection_if_hero_changed(socket, false), do: socket
end
