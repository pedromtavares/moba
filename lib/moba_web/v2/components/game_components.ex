defmodule MobaWeb.V2.Components.GameComponents do
  @moduledoc """
  Game-specific function components for BrowserMOBA v2.

  Displays heroes, skills, items, and other game entities.
  """
  use Phoenix.Component

  alias MobaWeb.V2.Components.GameHelpers, as: GH
  alias MobaWeb.V2.Components.StatTooltip
  alias MobaWeb.V2.Components.TooltipComponents, as: TT

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :tone, :string, default: "neutral", values: ~w(neutral active)
  slot :inner_block
  slot :actions

  def hud_notice(assigns) do
    ~H"""
    <section id={@id} class="hud-notice" data-tone={@tone} aria-labelledby={"#{@id}-title"}>
      <h3 id={"#{@id}-title"}>{@title}</h3>
      {render_slot(@inner_block)}
      <p :if={@description}>{@description}</p>
      <div :if={@actions != []} class="hud-notice-actions">{render_slot(@actions)}</div>
    </section>
    """
  end

  # -------------------------------------------------------------------
  # Skill Icon
  # -------------------------------------------------------------------

  @doc """
  Renders a skill icon with optional level badge and tooltip.

  ## Examples

      <.skill_icon skill={skill} size="md" show_level />
  """
  attr :skill, :map, required: true
  attr :size, :string, default: "md"
  attr :show_level, :boolean, default: false
  attr :class, :string, default: nil

  def skill_icon(assigns) do
    ~H"""
    <div
      class={[
        "relative rounded-full overflow-hidden flex-shrink-0",
        if(@skill.passive, do: "skill-passive-border", else: "ring-1 ring-white/20"),
        skill_icon_size(@size),
        @class
      ]}
      title={@skill.name}
    >
      <img src={GH.image_url(@skill)} alt={@skill.name} class="w-full h-full object-cover" loading="lazy" />
      <span
        :if={@show_level && @skill.level}
        class="absolute -bottom-px -right-px bg-surface text-[9px] text-gold font-bold w-3.5 h-3.5 flex items-center justify-center rounded-full border border-surface-border"
      >
        {@skill.level}
      </span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Item Slot
  # -------------------------------------------------------------------

  @doc """
  Renders an item icon with rarity-colored border and tooltip.

  ## Examples

      <.item_slot item={item} size="sm" />
  """
  attr :item, :map, required: true
  attr :size, :string, default: "md"
  attr :class, :string, default: nil

  def item_slot(assigns) do
    ~H"""
    <div
      class={[
        "relative overflow-hidden flex-shrink-0",
        "rounded border",
        item_rarity_border(@item.rarity),
        item_slot_size(@size),
        if(!@item.active, do: "opacity-70"),
        @class
      ]}
      title={@item.name}
    >
      <img src={GH.image_url(@item)} alt={@item.name} class="w-full h-full object-cover" loading="lazy" />
    </div>
    """
  end

  @doc """
  Renders a skill image using the current Bootstrap tooltip/icon markup.
  """
  attr :skill, :map, required: true
  attr :class, :string, default: "skill-img img-border-sm tooltip-mobile"
  attr :title, :string, default: nil
  attr :id, :string, default: nil
  attr :style, :string, default: nil

  def skill_image(assigns) do
    ~H"""
    <img
      src={GH.image_url(@skill)}
      class={[@class, @skill.passive && "passive"]}
      data-toggle="tooltip"
      title={@title || TT.skill_tooltip(@skill)}
      id={@id}
      style={@style}
      alt={@skill.name}
    />
    """
  end

  @doc """
  Renders a hero skill strip using the current Bootstrap card footer markup.
  """
  attr :skills, :list, required: true
  attr :container_class, :string, default: "skills-container d-flex justify-content-between"
  attr :image_class, :string, default: "skill-img img-border-sm tooltip-mobile"
  attr :id_prefix, :string, default: nil
  attr :id_suffix, :any, default: nil
  attr :tooltip_fun, :any, default: nil

  def hero_skill_strip(assigns) do
    ~H"""
    <div class={@container_class}>
      <.skill_image
        :for={skill <- @skills}
        skill={skill}
        class={@image_class}
        title={tooltip_for(@tooltip_fun, skill, &TT.skill_tooltip/1)}
        id={dom_id(@id_prefix, skill.id, @id_suffix)}
      />
    </div>
    """
  end

  @doc """
  Renders a hero item strip using the current Bootstrap card footer markup.
  """
  attr :items, :list, required: true
  attr :container_class, :string, default: "items-container row no-gutters"
  attr :image_class, :string, default: "item-img img-border-xs tooltip-mobile"
  attr :item_container_class, :string, default: "item-container col-4"
  attr :id_prefix, :string, default: nil
  attr :id_suffix, :any, default: nil
  attr :tooltip_fun, :any, default: nil

  def hero_item_strip(assigns) do
    ~H"""
    <div class={@container_class}>
      <div :for={item <- @items} class={@item_container_class}>
        <img
          src={GH.image_url(item)}
          class={[@image_class, !item.active && "passive"]}
          data-toggle="tooltip"
          title={tooltip_for(@tooltip_fun, item, &TT.item_tooltip/1)}
          id={dom_id(@id_prefix, item.id, @id_suffix)}
          alt={item.name}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a display-only hero stat with its tooltip.
  """
  attr :icon, :string, required: true
  attr :value, :any, required: true
  attr :variant, :string, default: "default"
  attr :title, :string, required: true
  attr :tone, :string, required: true
  attr :label, :string, default: nil

  def hero_stat_button(assigns) do
    ~H"""
    <span
      class={["game-stat", hero_stat_button_class(@variant, @tone)]}
      data-toggle="tooltip"
      title={@title}
      tabindex="0"
    >
      <i class={@icon} aria-hidden="true"></i> <span class="stat-value">{@value}</span>
      <small :if={@label} class="stat-label">{@label}</small>
    </span>
    """
  end

  @doc """
  Renders the standard six-stat hero readout.
  """
  attr :hero, :map, required: true
  attr :tooltip_mode, :string, default: "simple"
  attr :variant, :string, default: "default"

  def hero_stat_group(assigns) do
    ~H"""
    <div class={hero_stat_group_class(@variant)}>
      <.hero_stat_button
        variant={@variant}
        tone="danger"
        icon="ui-icon ui-heart mr-1"
        title={StatTooltip.title(@hero, :hp, @tooltip_mode)}
        value={@hero.total_hp + @hero.item_hp}
      />
      <.hero_stat_button
        variant={@variant}
        tone="info"
        icon="ui-icon ui-bolt"
        title={StatTooltip.title(@hero, :mp, @tooltip_mode)}
        value={@hero.total_mp + @hero.item_mp}
      />
      <.hero_stat_button
        variant={@variant}
        tone="success"
        icon="ui-icon ui-dagger"
        title={StatTooltip.title(@hero, :atk, @tooltip_mode)}
        value={@hero.atk + @hero.item_atk}
      />
      <.hero_stat_button
        variant={@variant}
        tone="pink"
        icon="ui-icon ui-vortex"
        title={StatTooltip.title(@hero, :power, @tooltip_mode)}
        value={@hero.power + @hero.item_power}
      />
      <.hero_stat_button
        variant={@variant}
        tone="warning"
        icon="ui-icon ui-shield"
        title={StatTooltip.title(@hero, :armor, @tooltip_mode)}
        value={@hero.armor + @hero.item_armor}
      />
      <.hero_stat_button
        variant={@variant}
        tone="orange"
        icon="ui-icon ui-runner"
        title={StatTooltip.title(@hero, :speed, @tooltip_mode)}
        value={@hero.speed + @hero.item_speed}
      />
    </div>
    """
  end

  @doc """
  Renders a battle stat row using explicit snapshot-aware values.
  """
  attr :hp, :any, required: true
  attr :mp, :any, required: true
  attr :atk, :any, required: true
  attr :power, :any, required: true
  attr :armor, :any, required: true
  attr :speed, :any, required: true
  attr :class, :string, default: "btn-group mt-1"

  def battle_hero_stat_group(assigns) do
    ~H"""
    <div class={@class}>
      <.hero_stat_button variant="default" tone="danger" icon="ui-icon ui-heart mr-1" title="Health" value={@hp} />
      <.hero_stat_button variant="default" tone="info" icon="ui-icon ui-bolt" title="Energy" value={@mp} />
      <.hero_stat_button variant="default" tone="success" icon="ui-icon ui-dagger" title="Attack" value={@atk} />
      <.hero_stat_button variant="default" tone="pink" icon="ui-icon ui-vortex" title="Power" value={@power} />
      <.hero_stat_button
        variant="default"
        tone="warning"
        icon="ui-icon ui-shield"
        title="Armor"
        value={@armor}
      />
      <.hero_stat_button
        variant="default"
        tone="orange"
        icon="ui-icon ui-runner"
        title="Speed"
        value={@speed}
      />
    </div>
    """
  end

  # -------------------------------------------------------------------
  # League Badge
  # -------------------------------------------------------------------

  @doc """
  Renders a league tier badge with image and name.
  """
  attr :tier, :integer, required: true
  attr :size, :string, default: "md"
  attr :show_name, :boolean, default: false
  attr :variant, :string, default: "modern"
  attr :class, :string, default: nil
  attr :img_class, :string, default: nil

  def league_badge(assigns) do
    ~H"""
    <%= if @variant == "legacy" do %>
      <img
        src={"/images/league/#{@tier}.png"}
        alt={GH.league_name(@tier)}
        class={["league-logo", @img_class]}
        loading="lazy"
      />
    <% else %>
      <div class={["inline-flex items-center gap-1", @class]} title={GH.league_name(@tier)}>
        <img
          src={"/images/league/#{@tier}.png"}
          alt={GH.league_name(@tier)}
          class={[league_badge_size(@size), @img_class]}
          loading="lazy"
        />
        <span :if={@show_name} class="text-xs text-faction-text-muted">{GH.league_name(@tier)}</span>
      </div>
    <% end %>
    """
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp skill_icon_size("sm"), do: "w-6 h-6"
  defp skill_icon_size("md"), do: "w-8 h-8"
  defp skill_icon_size("lg"), do: "w-10 h-10"
  defp skill_icon_size(_), do: "w-8 h-8"

  defp item_slot_size("sm"), do: "w-6 h-6"
  defp item_slot_size("md"), do: "w-8 h-8"
  defp item_slot_size("lg"), do: "w-10 h-10"
  defp item_slot_size(_), do: "w-8 h-8"

  defp league_badge_size("sm"), do: "w-5 h-5"
  defp league_badge_size("md"), do: "w-8 h-8"
  defp league_badge_size("lg"), do: "w-12 h-12"
  defp league_badge_size(_), do: "w-8 h-8"

  defp item_rarity_border("legendary"), do: "border-rarity-legendary/60"
  defp item_rarity_border("epic"), do: "border-rarity-epic/60"
  defp item_rarity_border("rare"), do: "border-rarity-rare/60"
  defp item_rarity_border(_), do: "border-white/10"

  defp hero_stat_group_class("hero_bar"), do: "btn-group stats-group f-rpg"
  defp hero_stat_group_class(_), do: "btn-group hero-stats"

  defp hero_stat_button_class("hero_bar", tone) do
    "btn btn-icon btn-outline-dark #{tone_class(tone)} tooltip-mobile no-action"
  end

  defp hero_stat_button_class(_, "danger"), do: "btn btn-icon waves-effect btn-outline-dark text-danger"
  defp hero_stat_button_class(_, tone), do: "btn btn-icon waves-effect waves-light btn-outline-dark #{tone_class(tone)}"

  defp tone_class("danger"), do: "text-danger"
  defp tone_class("info"), do: "text-info"
  defp tone_class("success"), do: "text-success"
  defp tone_class("pink"), do: "text-pink"
  defp tone_class("warning"), do: "text-warning"
  defp tone_class("orange"), do: "text-orange"

  defp tooltip_for(nil, value, default_fun), do: default_fun.(value)
  defp tooltip_for(fun, value, _default_fun), do: fun.(value)

  defp dom_id(nil, _id, _suffix), do: nil
  defp dom_id(prefix, id, nil), do: "#{prefix}-#{id}"
  defp dom_id(prefix, id, suffix), do: "#{prefix}-#{id}-#{suffix}"
end
