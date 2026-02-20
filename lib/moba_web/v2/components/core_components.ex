defmodule MobaWeb.V2.Components.CoreComponents do
  @moduledoc """
  Core UI components for BrowserMOBA v2.
  """
  use Phoenix.Component

  # -------------------------------------------------------------------
  # Button
  # -------------------------------------------------------------------

  @doc """
  Renders a themed button.

  ## Variants
    - `"primary"` — gold border + glow (MainMenuButton equivalent)
    - `"secondary"` — subtle border (SmallButton equivalent)
    - `"danger"` — red accent
    - `"confirm"` — compact confirm (DialogButton equivalent)

  ## Examples

      <.button variant="primary" phx-click="start">Start Game</.button>
      <.button variant="secondary" disabled>Locked</.button>
  """
  attr :variant, :string, default: "primary"
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-target phx-disable-with)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      class={[
        "inline-flex items-center justify-center font-medium transition-all duration-150 cursor-pointer",
        "disabled:opacity-40 disabled:cursor-not-allowed",
        button_variant_classes(@variant),
        @class
      ]}
      disabled={@disabled}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  # -------------------------------------------------------------------
  # Tab Bar
  # -------------------------------------------------------------------

  @doc """
  Renders a tab bar (FactionTab equivalent).
  Text turns gold on active.

  ## Examples

      <.tab_bar>
        <.tab active={@filter == "unfinished"} phx-click="filter" phx-value-filter="unfinished">
          In Training
        </.tab>
        <.tab active={@filter == "finished"} phx-click="filter" phx-value-filter="finished">
          Finished
        </.tab>
      </.tab_bar>
  """
  slot :inner_block, required: true
  attr :class, :string, default: nil

  def tab_bar(assigns) do
    ~H"""
    <div class={["flex gap-1 border-b border-surface-border pb-px", @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :active, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-filter phx-value-tab phx-target)
  slot :inner_block, required: true

  def tab(assigns) do
    ~H"""
    <button
      class={[
        "px-4 py-2 text-sm font-medium transition-colors duration-150 border-b-2 -mb-px cursor-pointer",
        if(@active,
          do: "text-gold border-gold",
          else: "text-faction-text-muted border-transparent hover:text-faction-text hover:border-faction-accent/50"
        ),
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  # -------------------------------------------------------------------
  # Panel
  # -------------------------------------------------------------------

  @doc """
  Renders a bordered panel container (Menu border panel equivalent).

  ## Examples

      <.panel title="Your Heroes">
        <p>Content here</p>
      </.panel>
  """
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <div class={[
      "bg-surface border border-surface-border rounded",
      @class
    ]}>
      <div :if={@title} class="px-4 py-3 border-b border-surface-border">
        <h2 class="text-gold font-semibold text-lg"><%= @title %></h2>
      </div>
      <div class="p-4">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Flash
  # -------------------------------------------------------------------

  @doc """
  Renders flash messages.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <.flash :if={Phoenix.Flash.get(@flash, :info)} kind="info" message={Phoenix.Flash.get(@flash, :info)} />
    <.flash :if={Phoenix.Flash.get(@flash, :error)} kind="error" message={Phoenix.Flash.get(@flash, :error)} />
    """
  end

  attr :kind, :string, required: true
  attr :message, :string, required: true

  def flash(assigns) do
    ~H"""
    <div class={[
      "px-4 py-3 rounded mb-4 text-sm border",
      flash_classes(@kind)
    ]}>
      <%= @message %>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Badge
  # -------------------------------------------------------------------

  @doc """
  Renders a colored badge.

  ## Examples

      <.badge color="gold">Legendary</.badge>
      <.badge color="green">+50 HP</.badge>
  """
  attr :color, :string, default: "gray"
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
      badge_color_classes(@color),
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  # -------------------------------------------------------------------
  # Health Bar
  # -------------------------------------------------------------------

  @doc """
  Renders a health bar with green fill.

  ## Examples

      <.health_bar current={350} max={500} />
  """
  attr :current, :integer, required: true
  attr :max, :integer, required: true
  attr :label, :string, default: nil
  attr :class, :string, default: nil

  def health_bar(assigns) do
    assigns = assign(assigns, :pct, bar_percentage(assigns.current, assigns.max))

    ~H"""
    <div class={["bar-track", @class]}>
      <div class="bar-fill bg-hp" style={"width: #{@pct}%"}></div>
      <span class="bar-label">
        <%= @label || "#{@current} / #{@max}" %>
      </span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Mana Bar
  # -------------------------------------------------------------------

  @doc """
  Renders a mana bar with blue fill.

  ## Examples

      <.mana_bar current={200} max={300} />
  """
  attr :current, :integer, required: true
  attr :max, :integer, required: true
  attr :label, :string, default: nil
  attr :class, :string, default: nil

  def mana_bar(assigns) do
    assigns = assign(assigns, :pct, bar_percentage(assigns.current, assigns.max))

    ~H"""
    <div class={["bar-track", @class]}>
      <div class="bar-fill bg-mp" style={"width: #{@pct}%"}></div>
      <span class="bar-label">
        <%= @label || "#{@current} / #{@max}" %>
      </span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # XP Bar
  # -------------------------------------------------------------------

  @doc """
  Renders an XP bar with purple fill.

  ## Examples

      <.xp_bar level={5} current_xp={300} max_xp={1000} />
  """
  attr :level, :integer, required: true
  attr :current_xp, :integer, required: true
  attr :max_xp, :integer, required: true
  attr :class, :string, default: nil

  def xp_bar(assigns) do
    assigns = assign(assigns, :pct, bar_percentage(assigns.current_xp, assigns.max_xp))

    ~H"""
    <div class={["bar-track", @class]}>
      <div class="bar-fill bg-speed" style={"width: #{@pct}%"}></div>
      <span class="bar-label">
        Level <%= @level %> · <%= @pct %>%
      </span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Progress Bar
  # -------------------------------------------------------------------

  @doc """
  Renders a generic progress bar.

  ## Examples

      <.progress_bar value={42} color="gold" label="Training Progress" />
  """
  attr :value, :integer, required: true
  attr :color, :string, default: "accent"
  attr :label, :string, default: nil
  attr :class, :string, default: nil

  def progress_bar(assigns) do
    ~H"""
    <div class={["bar-track", @class]}>
      <div class={["bar-fill", progress_color(@color)]} style={"width: #{min(@value, 100)}%"}></div>
      <span class="bar-label">
        <%= @label || "#{@value}%" %>
      </span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Resource Counter
  # -------------------------------------------------------------------

  @doc """
  Renders an animated resource counter with icon.

  ## Examples

      <.resource_counter value={2580} icon="gold" />
      <.resource_counter value={500} icon="shard" label="Shards" />
  """
  attr :value, :any, required: true
  attr :icon, :string, default: "gold"
  attr :label, :string, default: nil
  attr :class, :string, default: nil

  def resource_counter(assigns) do
    ~H"""
    <div class={["inline-flex items-center gap-1.5", @class]}>
      <span class={["text-sm", resource_icon_class(@icon)]}>
        <%= resource_icon_char(@icon) %>
      </span>
      <span class="font-semibold text-sm tabular-nums">
        <%= format_number(@value) %>
      </span>
      <span :if={@label} class="text-xs text-faction-text-muted"><%= @label %></span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Empty State
  # -------------------------------------------------------------------

  @doc """
  Renders a centered empty state message.

  ## Examples

      <.empty_state message="No heroes found. Create one to get started!" />
  """
  attr :message, :string, required: true
  attr :class, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div class={["text-center py-12 text-faction-text-muted italic", @class]}>
      <%= @message %>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp button_variant_classes("primary") do
    "px-4 py-2 text-sm bg-surface border border-gold/70 text-gold rounded hover:bg-gold/10 hover:border-gold hover:shadow-[0_0_8px_rgba(224,165,38,0.3)]"
  end

  defp button_variant_classes("secondary") do
    "px-3 py-1.5 text-sm bg-surface border border-surface-border text-faction-text rounded hover:border-surface-border-light hover:text-faction-text"
  end

  defp button_variant_classes("danger") do
    "px-4 py-2 text-sm bg-surface border border-atk/50 text-atk rounded hover:bg-atk/10 hover:border-atk"
  end

  defp button_variant_classes("confirm") do
    "px-3 py-1.5 text-sm bg-gold/10 border border-gold/50 text-gold rounded hover:bg-gold/20"
  end

  defp button_variant_classes(_), do: button_variant_classes("secondary")

  defp flash_classes("info"), do: "bg-surface-light border-faction-accent/50 text-faction-text"
  defp flash_classes("error"), do: "bg-atk/10 border-atk/50 text-atk-light"
  defp flash_classes(_), do: flash_classes("info")

  defp badge_color_classes("green"), do: "bg-hp/20 text-hp-light"
  defp badge_color_classes("blue"), do: "bg-mp/20 text-mp-light"
  defp badge_color_classes("red"), do: "bg-atk/20 text-atk-light"
  defp badge_color_classes("purple"), do: "bg-speed/20 text-speed-light"
  defp badge_color_classes("gold"), do: "bg-gold/20 text-gold-light"
  defp badge_color_classes("pink"), do: "bg-power/20 text-power-light"
  defp badge_color_classes(_), do: "bg-white/10 text-faction-text-muted"

  defp bar_percentage(_current, 0), do: 0
  defp bar_percentage(current, max), do: min(round(current / max * 100), 100)

  defp progress_color("gold"), do: "bg-gold"
  defp progress_color("green"), do: "bg-hp"
  defp progress_color("blue"), do: "bg-mp"
  defp progress_color("red"), do: "bg-atk"
  defp progress_color("pve"), do: "bg-pve"
  defp progress_color("accent"), do: "bg-faction-accent"
  defp progress_color(_), do: "bg-faction-accent"

  defp resource_icon_class("gold"), do: "text-gold"
  defp resource_icon_class("xp"), do: "text-speed"
  defp resource_icon_class("shard"), do: "text-faction-accent"
  defp resource_icon_class(_), do: "text-faction-text-muted"

  defp resource_icon_char("gold"), do: "⚜"
  defp resource_icon_char("xp"), do: "★"
  defp resource_icon_char("shard"), do: "◆"
  defp resource_icon_char(_), do: "●"

  defp format_number(value) when is_integer(value) and value >= 1000 do
    "#{div(value, 1000)}K"
  end

  defp format_number(value), do: value
end
