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

  attr :items, :list, required: true
  attr :costs, :map, required: true
  attr :selected, :map, default: nil
  attr :id_prefix, :string, required: true
  attr :event_target, :any, required: true

  def forge_picker(assigns) do
    ~H"""
    <section
      id={GH.dom_id(@id_prefix, "forge-picker")}
      class="shop-shelf shop-forge-picker is-current"
      data-rarity="epic"
      aria-labelledby={GH.dom_id(@id_prefix, "forge-picker-title")}
    >
      <div id={GH.dom_id(@id_prefix, "forge-choices")} class="shop-forge-grid" phx-mounted={JS.focus_first()}>
        <%= for item <- @items do %>
          <% cost = @costs[item.code]
          selected? = @selected && @selected.code == item.code %>
          <button
            id={GH.dom_id(@id_prefix, "forge-epic-#{item.code}")}
            type="button"
            class={["shop-tile shop-forge-choice", selected? && "is-selected"]}
            phx-click="choose-forge-epic"
            phx-value-code={item.code}
            phx-target={@event_target}
            disabled={is_nil(cost)}
            aria-pressed={to_string(!!selected?)}
          >
            <span class="shop-forge-choice-art">
              <img src={GH.image_url(item)} alt="" />
            </span>
            <span class="shop-forge-choice-info">
              <span class="shop-forge-choice-name">{item.name}</span>
              <span class="shop-forge-choice-price">
                <%= if is_integer(cost) && cost != 0 do %>
                  <span :if={cost < 0} class="shop-forge-price-label">Refund</span>
                  <span class="shop-forge-gold">
                    <.icon name="game-gold" />
                    <strong>{abs(cost)}</strong> <span class="shop-forge-price-label">gold</span>
                  </span>
                <% else %>
                  <span class="shop-forge-price-label">{forge_cost_label(cost)}</span>
                <% end %>
              </span>
            </span>
          </button>
        <% end %>
      </div>
    </section>
    """
  end

  attr :legendary, :map, required: true
  attr :epic, :map, default: nil
  attr :id_prefix, :string, required: true

  def forge_showcase(assigns) do
    ~H"""
    <div class="shop-item-showcase shop-forge-showcase" data-forge-preview={to_string(!is_nil(@epic))}>
      <div class="shop-forge-sockets" aria-hidden="true">
        <div class="shop-forge-socket" data-rarity="legendary">
          <img src={GH.image_url(@legendary)} alt="" />
        </div>
        <.icon name="game-plus" class="shop-forge-join" />
        <div class={["shop-forge-socket", !@epic && "is-empty"]} data-rarity="epic">
          <%= if @epic do %>
            <img id={GH.dom_id(@id_prefix, "forge-preview-#{@epic.code}")} src={GH.image_url(@epic)} alt="" />
          <% else %>
            <span>Epic</span>
          <% end %>
        </div>
      </div>
      <div class="shop-item-identity" aria-live="polite">
        <span class="shop-eyebrow">{if @epic, do: "Forged Legendary", else: "Forge"}</span>
        <h3 id={GH.dom_id(@id_prefix, "shop-detail-name")} class="shop-detail-name">
          {if @epic, do: "Forged #{@legendary.name}", else: @legendary.name}
        </h3>
        <p :if={@epic} class="shop-forged-epic">+ {@epic.name}</p>
      </div>
    </div>
    """
  end

  def forge_cost_label(nil), do: "Already forged"
  def forge_cost_label(cost) when cost < 0, do: "Refund #{-cost} gold"
  def forge_cost_label(0), do: "Free"
  def forge_cost_label(cost), do: "#{cost} gold"

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
          {if @transmuting, do: "Transmute", else: GH.item_rarity_name(@item)}
          <span :if={!Map.has_key?(@item, :forged_epic)} class="shop-item-kind">
            {if @item.active, do: "Active item", else: "Passive item"}
          </span>
        </span>
        <h3 id={GH.dom_id(@id_prefix, "shop-detail-name")} class="shop-detail-name">
          {if Map.has_key?(@item, :forged_epic), do: "Forged #{@item.name}", else: @item.name}
        </h3>
        <p :if={epic = Map.get(@item, :forged_epic)} class="shop-forged-epic">+ {epic.name}</p>
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
