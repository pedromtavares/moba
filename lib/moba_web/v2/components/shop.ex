defmodule MobaWeb.V2.Components.Shop do
  use MobaWeb, :v2_html

  import MobaWeb.CoreComponents, only: [icon: 1]

  attr :rarity, :string, required: true
  attr :items, :list, required: true
  attr :selected_category, :string, default: nil
  attr :selected_item, :map, default: nil
  attr :owned_items, :list, default: []
  attr :id_prefix, :string, required: true
  attr :event_target, :any, default: nil
  attr :catalog, :boolean, default: false

  def shelf(assigns) do
    ~H"""
    <section
      id={GH.dom_id(@id_prefix, "shop-shelf-#{@rarity}")}
      class={["shop-shelf", "#{@rarity}-items", !@catalog && @selected_category == @rarity && "is-current"]}
      data-rarity={@rarity}
    >
      <% first_item = List.first(@items) %>
      <button
        type="button"
        id={GH.dom_id(@id_prefix, "shop-category-#{@rarity}")}
        class="shop-shelf-label"
        phx-click={unless @catalog, do: "select-category"}
        phx-value-rarity={unless @catalog, do: @rarity}
        phx-target={@event_target}
        data-manual-pick={@catalog && first_item && "item-category"}
        data-manual-rarity={@catalog && @rarity}
        data-code={@catalog && first_item && first_item.code}
        disabled={@catalog && is_nil(first_item)}
        aria-pressed={to_string(@selected_category == @rarity)}
      >
        <span>{String.capitalize(@rarity)}</span>
        <small><.icon name="game-gold" /> {category_price(@rarity)}</small>
      </button>
      <div class="shop-miniatures">
        <button
          :for={item <- @items}
          type="button"
          id={GH.dom_id(@id_prefix, "item-#{item.id}")}
          class={["shop-tile", !@catalog && @selected_item && @selected_item.code == item.code && "is-selected"]}
          aria-label={item.name}
          aria-pressed={to_string((@selected_item && @selected_item.code == item.code) || false)}
          phx-click={unless @catalog, do: "select-shop"}
          phx-value-code={unless @catalog, do: item.code}
          phx-target={@event_target}
          data-manual-pick={@catalog && "item"}
          data-code={@catalog && item.code}
          aria-controls={@catalog && GH.dom_id(@id_prefix, "item-detail-#{item.code}")}
        >
          <img
            src={GH.image_url(item)}
            alt=""
            class={"code-#{item.code} tooltip-mobile"}
            data-toggle="tooltip"
            title={TT.item_tooltip(item)}
          />
          <span :if={Enum.any?(@owned_items, &(&1.code == item.code))} class="shop-owned" aria-label="Owned">✓</span>
        </button>
      </div>
    </section>
    """
  end

  attr :item, :map, required: true
  attr :id_prefix, :string, required: true
  attr :transmuting, :boolean, default: false

  def item_showcase(assigns) do
    ~H"""
    <div class="shop-item-showcase">
      <div class="shop-item-aura" aria-hidden="true"></div>
      <img
        id={GH.dom_id(@id_prefix, "shop-detail-image")}
        class="shop-detail-image"
        src={GH.image_url(@item)}
        alt={@item.name}
      />
      <div class="shop-item-identity">
        <span class="shop-eyebrow">
          {if @transmuting, do: "Transmute", else: String.capitalize(@item.rarity)}<span class="shop-item-kind">{if @item.active, do: "Active item", else: "Passive item"}</span>
        </span>
        <h3 id={GH.dom_id(@id_prefix, "shop-detail-name")} class="shop-detail-name">{@item.name}</h3>
      </div>
    </div>
    """
  end

  def categories, do: ["normal", "rare", "epic", "legendary"]

  defp category_price("normal"), do: Moba.normal_items_price()
  defp category_price("rare"), do: Moba.rare_items_price()
  defp category_price("epic"), do: Moba.epic_items_price()
  defp category_price("legendary"), do: Moba.legendary_items_price()

  def rarity_filter(items, rarity) do
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
end
