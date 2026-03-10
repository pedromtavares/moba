defmodule MobaWeb.V2.Components.ShopComponents do
  use Phoenix.Component

  alias MobaWeb.V2.Components.GameHelpers, as: GH
  alias MobaWeb.V2.Components.TooltipComponents, as: TT

  attr :item, :map, required: true
  attr :target, :string, default: "#shop"

  def shop_item(assigns) do
    ~H"""
    <div class="col-4 col-md-4 mb-2 d-flex justify-content-center">
      <img
        src={GH.image_url(@item)}
        data-toggle="tooltip"
        title={TT.item_tooltip(@item)}
        class={"item-img code-#{@item.code} tooltip-mobile #{if @item.active, do: "active"}"}
        phx-click="select-shop"
        phx-value-code={@item.code}
        phx-target={@target}
        id={"item-#{@item.id}"}
      />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :class, :string, default: "item-img"
  attr :id, :string, default: nil
  attr :target, :string, default: nil
  attr :click, :string, default: nil
  attr :code, :string, default: nil

  def shop_item_image(assigns) do
    ~H"""
    <img
      src={GH.image_url(@item)}
      data-toggle="tooltip"
      title={TT.item_tooltip(@item)}
      class={@class}
      phx-click={@click}
      phx-value-code={@code}
      phx-target={@target}
      id={@id}
    />
    """
  end

  attr :item, :map, required: true
  attr :selectable, :boolean, default: false
  attr :target, :string, default: "#shop"

  def inventory_item(assigns) do
    ~H"""
    <div class="col-4 col-md-2 inventory-item">
      <%= if @selectable do %>
        <.shop_item_image
          item={@item}
          class={if @item.active, do: "item-img active", else: "item-img"}
          click="select-inventory"
          code={@item.code}
          target={@target}
          id={"transmute-#{@item.id}"}
        />
      <% else %>
        <.shop_item_image item={@item} class="item-img inactive" />
      <% end %>
    </div>
    """
  end

  attr :icon_class, :string, default: nil
  attr :class, :string, default: "item-img empty-item"

  def shop_empty_item_slot(assigns) do
    ~H"""
    <div class={@class}>
      <i :if={@icon_class} class={@icon_class}></i>
    </div>
    """
  end

  attr :item, :map, required: true

  def selected_item(assigns) do
    ~H"""
    <div class="row selected-shop">
      <div class="col center d-flex justify-content-center">
        <.shop_item_image item={@item} />
      </div>
    </div>
    """
  end

  attr :selected_shop, :map, required: true
  attr :buy_enabled, :boolean, required: true
  attr :transmute_enabled, :boolean, required: true
  attr :price, :integer, required: true
  attr :event_target, :any, default: nil

  def shop_actions(assigns) do
    ~H"""
    <hr class="img-border-xs" />
    <.selected_item item={@selected_shop} />
    <hr />
    <div class="row">
      <div class="col center">
        <button
          class="btn btn-warning buy-button"
          phx-click="buy"
          phx-value-code={@selected_shop.code}
          disabled={!@buy_enabled}
          phx-hook="Loading"
          loading="Buying..."
          id="buy-button"
          {target_attrs(@event_target)}
        >
          <span class="loading-text">Buy for <i class="fa fa-coins"></i> {@price}</span>
        </button>
        <%= unless @selected_shop.rarity == "normal" do %>
          <button
            class="btn btn-primary transmute-button"
            phx-click="start-transmute"
            phx-target="#shop"
            disabled={!@transmute_enabled}
          >
            <i class="fa fa-refresh"></i> Transmute
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  def recipe_item(assigns) do
    ~H"""
    <div class="col-4 col-md-2">
      <.shop_item_image item={@item} class="item-img" id={"recipe-#{@item.id}"} />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :class, :string, default: "item-img float-right"

  def transmute_result(assigns) do
    ~H"""
    <.shop_item_image item={@item} class={@class} />
    """
  end

  defp target_attrs(nil), do: %{}
  defp target_attrs(target), do: %{"phx-target" => target}
end
