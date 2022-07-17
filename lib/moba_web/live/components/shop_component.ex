defmodule MobaWeb.Shop do
  use MobaWeb, :live_component

  alias MobaWeb.TutorialComponent

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

  def update(%{current_hero: hero, tutorial_step: step}, socket) do
    {:ok,
     assign(socket,
       items: Moba.cached_items(),
       current_hero: hero,
       tutorial_step: step,
       current_player: hero.player
     )}
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

  def handle_event("finish-transmute", _, %{assigns: assigns} = socket) do
    hero = Game.transmute_item!(assigns.current_hero, assigns.recipe, assigns.transmute)
    Game.broadcast_to_hero(hero.id)

    {:noreply, assign(socket, transmute: nil, recipe: []) |> TutorialComponent.next_step(9)}
  end

  def handle_event("buy", _, %{assigns: assigns} = socket) do
    hero = Game.buy_item!(assigns.current_hero, assigns.selected_shop)
    Game.broadcast_to_hero(hero.id)

    {:noreply, assign(socket, selected_shop: nil) |> check_tutorial(hero)}
  end

  def handle_event("sell", _, %{assigns: assigns} = socket) do
    hero = Game.sell_item!(assigns.current_hero, assigns.selected_inventory)
    Game.broadcast_to_hero(hero.id)

    {:noreply, assign(socket, selected_inventory: nil)}
  end

  def subscribe(hero_id) do
    MobaWeb.subscribe("shop-#{hero_id}")
    hero_id
  end

  def open(socket) do
    broadcast(socket, "open-shop")
  end

  def close(socket) do
    broadcast(socket, "close-shop")
  end

  def toggle(socket) do
    broadcast(socket, "toggle-shop")
  end

  def render(assigns) do
    MobaWeb.ShopView.render("shop.html", assigns)
  end

  defp broadcast(%{assigns: assigns} = socket, event) do
    hero_id = assigns.current_hero.id
    MobaWeb.broadcast("shop-#{hero_id}", event, %{})
    socket
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

  defp check_tutorial(%{assigns: %{tutorial_step: step}} = socket, hero) do
    if length(hero.items) > 1 && step == 3 do
      socket
      |> TutorialComponent.next_step(4)
      |> close()
    else
      socket |> TutorialComponent.next_step(7)
    end
  end
end
