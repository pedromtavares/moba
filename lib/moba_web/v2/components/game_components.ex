defmodule MobaWeb.V2.Components.GameComponents do
  @moduledoc """
  Game-specific function components for BrowserMOBA v2.

  Displays heroes, skills, items, and other game entities.
  """
  use Phoenix.Component

  alias MobaWeb.V2.Components.GameHelpers, as: GH

  # -------------------------------------------------------------------
  # Portrait Frame
  # -------------------------------------------------------------------

  @doc """
  Renders a hero avatar in a decorative frame.

  ## Examples

      <.portrait_frame src={GH.image_url(hero.avatar)} size="md" />
  """
  attr :src, :string, required: true
  attr :size, :string, default: "md"
  attr :class, :string, default: nil

  def portrait_frame(assigns) do
    ~H"""
    <div class={["relative overflow-hidden rounded portrait-border", portrait_size(@size), @class]}>
      <img src={@src} alt="" class="w-full h-full object-cover" loading="lazy" />
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Hero Card
  # -------------------------------------------------------------------

  @doc """
  Renders a hero display card with portrait, name, level, stats, skills, items.

  ## Examples

      <.hero_card hero={hero}>
        <:actions>
          <.button phx-click="continue" phx-value-id={hero.id}>Continue</.button>
        </:actions>
      </.hero_card>
  """
  attr :hero, :map, required: true
  attr :class, :string, default: nil
  slot :actions

  def hero_card(assigns) do
    ~H"""
    <div
      id={"hero-card-#{@hero.id}"}
      class={["hero-card-border min-h-[380px] flex flex-col bg-cover bg-center overflow-hidden", @class]}
      style={"background-image: url('#{GH.background_url(@hero)}')"}
    >
      <%!-- Header --%>
      <div class="px-3 pt-2 pb-1 flex justify-between items-center bg-[rgba(54,64,74,0.8)]">
        <span class="italic text-xl text-white font-rpg leading-none w-12 shrink-0">
          <%= if @hero.pve_ranking, do: "##{@hero.pve_ranking}" %>
        </span>
        <div class="flex items-center gap-1 font-bold text-white">
          <.league_badge tier={@hero.league_tier} size="sm" />
          <%= @hero.name || @hero.avatar.name %>
        </div>
        <span class="italic text-sm text-white text-right w-28 shrink-0" title={hero_stats_title(@hero)}>
          Level <%= @hero.level %> <%= @hero.avatar.name %>
        </span>
      </div>

      <%!-- Body (empty — background image shows through) --%>
      <div class="flex-1"></div>

      <%!-- Footer --%>
      <div class="p-1 bg-[rgba(54,64,74,0.95)]">
        <%!-- Actions row: delete / continue / customize / farming --%>
        <div :if={@actions != []} class="flex items-center px-1 py-1">
          <%= render_slot(@actions) %>
        </div>
        <%!-- Skills + Items row --%>
        <div class="flex items-start justify-between px-1 pt-1">
          <div class="flex gap-0.5 w-[70%]">
            <.skill_icon :for={skill <- @hero.skills} skill={skill} size="sm" />
          </div>
          <div class="flex flex-wrap gap-0.5 justify-end w-[30%]">
            <.item_slot :for={item <- sort_items(@hero.items)} item={item} size="sm" />
          </div>
        </div>
      </div>
    </div>
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
        <%= @skill.level %>
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

  # -------------------------------------------------------------------
  # Hero Stats (compact inline)
  # -------------------------------------------------------------------

  @doc """
  Renders hero stats as a compact inline row.

  ## Examples

      <.hero_stats_compact hero={hero} />
  """
  attr :hero, :map, required: true
  attr :show_speed, :boolean, default: false
  attr :class, :string, default: nil

  def hero_stats_compact(assigns) do
    ~H"""
    <div class={["flex flex-wrap gap-x-3 gap-y-0.5 text-xs", @class]}>
      <span><span class="text-hp">HP</span> <span class="text-faction-text tabular-nums"><%= @hero.total_hp %></span></span>
      <span><span class="text-mp">MP</span> <span class="text-faction-text tabular-nums"><%= @hero.total_mp %></span></span>
      <span><span class="text-atk">ATK</span> <span class="text-faction-text tabular-nums"><%= @hero.atk %></span></span>
      <span>
        <span class="text-power">POW</span> <span class="text-faction-text tabular-nums"><%= @hero.power %></span>
      </span>
      <span>
        <span class="text-armor">ARM</span> <span class="text-faction-text tabular-nums"><%= @hero.armor %></span>
      </span>
      <span :if={@show_speed}>
        <span class="text-speed">SPD</span> <span class="text-faction-text tabular-nums"><%= @hero.speed %></span>
      </span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Hero Stats (full display)
  # -------------------------------------------------------------------

  @doc """
  Renders a full hero stats display in a grid layout.
  """
  attr :hero, :map, required: true
  attr :class, :string, default: nil

  def hero_stats(assigns) do
    ~H"""
    <div class={["grid grid-cols-3 gap-2 text-sm", @class]}>
      <.stat_item label="HP" value={@hero.total_hp} color="hp" />
      <.stat_item label="MP" value={@hero.total_mp} color="mp" />
      <.stat_item label="ATK" value={@hero.atk} color="atk" />
      <.stat_item label="Power" value={@hero.power} color="power" />
      <.stat_item label="Armor" value={@hero.armor} color="armor" />
      <.stat_item label="Speed" value={@hero.speed} color="speed" />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, required: true

  defp stat_item(assigns) do
    ~H"""
    <div class="flex items-center justify-between bg-surface-dark/50 rounded px-2 py-1">
      <span class={["text-xs font-medium", stat_color(@color)]}><%= @label %></span>
      <span class="text-faction-text font-semibold tabular-nums text-xs"><%= @value %></span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Avatar Card
  # -------------------------------------------------------------------

  @doc """
  Renders an avatar selection card.
  """
  attr :avatar, :map, required: true
  attr :selected, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-target)

  def avatar_card(assigns) do
    ~H"""
    <div
      class={[
        "relative rounded overflow-hidden cursor-pointer transition-all duration-150",
        "border-2",
        if(@selected,
          do: "border-gold shadow-[0_0_8px_rgba(224,165,38,0.4)]",
          else: "border-surface-border hover:border-faction-accent/50"
        ),
        @class
      ]}
      {@rest}
    >
      <div class="relative w-full aspect-square">
        <img src={GH.image_url(@avatar)} alt={@avatar.name} class="w-full h-full object-cover" loading="lazy" />
        <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 to-transparent p-2">
          <div class="text-xs font-semibold text-white truncate"><%= @avatar.name %></div>
          <div :if={@avatar.role} class="text-[10px] text-faction-text-muted"><%= GH.role_name(@avatar.role) %></div>
        </div>
      </div>
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
  attr :class, :string, default: nil

  def league_badge(assigns) do
    ~H"""
    <div class={["inline-flex items-center gap-1", @class]} title={GH.league_name(@tier)}>
      <img src={"/images/league/#{@tier}.png"} alt={GH.league_name(@tier)} class={league_badge_size(@size)} loading="lazy" />
      <span :if={@show_name} class="text-xs text-faction-text-muted"><%= GH.league_name(@tier) %></span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # PvE Progression
  # -------------------------------------------------------------------

  @doc """
  Renders the PvE tier progression display.
  """
  attr :player, :map, required: true
  attr :class, :string, default: nil

  def pve_progression(assigns) do
    ~H"""
    <div class={["flex items-center gap-3", @class]}>
      <div class="flex items-center gap-2">
        <img src={"/images/pve/#{@player.pve_tier}.png"} alt="" class="w-8 h-8" loading="lazy" />
        <div>
          <div class="text-sm font-semibold text-gold"><%= GH.pve_tier_name(@player.pve_tier) %></div>
          <div class="text-xs text-faction-text-muted">PvE Tier <%= @player.pve_tier %></div>
        </div>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp portrait_size("sm"), do: "w-10 h-10"
  defp portrait_size("md"), do: "w-16 h-16"
  defp portrait_size("lg"), do: "w-24 h-24"
  defp portrait_size(_), do: "w-16 h-16"

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

  defp stat_color("hp"), do: "text-hp"
  defp stat_color("mp"), do: "text-mp"
  defp stat_color("atk"), do: "text-atk"
  defp stat_color("power"), do: "text-power"
  defp stat_color("armor"), do: "text-armor"
  defp stat_color("speed"), do: "text-speed"
  defp stat_color(_), do: "text-faction-text-muted"

  defp sort_items(items) when is_list(items), do: Enum.sort_by(items, fn item -> !item.active end)
  defp sort_items(_), do: []

  defp hero_stats_title(hero) do
    "HP: #{hero.total_hp} | MP: #{hero.total_mp} | ATK: #{hero.atk} | POW: #{hero.power} | ARM: #{hero.armor} | SPD: #{hero.speed}"
  end
end
