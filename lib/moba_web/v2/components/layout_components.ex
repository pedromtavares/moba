defmodule MobaWeb.V2.Components.LayoutComponents do
  @moduledoc """
  Layout function components for BrowserMOBA v2.

  Replaces v1's SidebarLive, CurrentHeroLive, CurrentPlayerLive
  with function components rendered in the app layout.
  """
  use Phoenix.Component

  import MobaWeb.V2.Components.CoreComponents
  import MobaWeb.V2.Components.GameComponents

  alias MobaWeb.V2.Components.GameHelpers, as: GH

  use Phoenix.VerifiedRoutes,
    endpoint: MobaWeb.Endpoint,
    router: MobaWeb.Router,
    statics: MobaWeb.static_paths()

  @nav_items [
    %{code: "base", label: "Base", path: "/v2/base", icon: "⚔"},
    %{code: "library", label: "Library", path: "/v2/library", icon: "📖"}
  ]

  # -------------------------------------------------------------------
  # Sidebar
  # -------------------------------------------------------------------

  @doc """
  Renders the navigation sidebar with player info and current hero.
  """
  attr :current_player, :map, default: nil
  attr :current_hero, :map, default: nil
  attr :sidebar_code, :string, default: nil

  def sidebar(assigns) do
    assigns = assign(assigns, :nav_items, @nav_items)

    ~H"""
    <aside data-role="sidebar" class="w-56 flex-shrink-0 bg-surface border-r border-surface-border flex flex-col min-h-screen">
      <%!-- Logo / Title --%>
      <div class="px-4 py-4 border-b border-surface-border">
        <a href={~p"/v2/base"} class="text-gold font-bold text-lg tracking-wide hover:text-gold-light transition-colors">
          BrowserMOBA
        </a>
      </div>

      <%!-- Navigation --%>
      <nav class="px-2 py-3 space-y-0.5">
        <a
          :for={item <- @nav_items}
          href={item.path}
          class={[
            "flex items-center gap-2.5 px-3 py-2 rounded text-sm transition-colors duration-150",
            if(@sidebar_code == item.code,
              do: "bg-surface-light text-gold",
              else: "text-faction-text-muted hover:text-faction-text hover:bg-surface-light/50"
            )
          ]}
        >
          <span class="text-base"><%= item.icon %></span>
          <span><%= item.label %></span>
        </a>
      </nav>

      <%!-- Player Info --%>
      <div :if={@current_player} class="px-3 py-3 mt-auto border-t border-surface-border">
        <div class="text-xs text-faction-text-muted uppercase tracking-wide mb-2">Player</div>
        <div class="space-y-1.5">
          <div class="flex items-center gap-2">
            <img src={"/images/pve/#{@current_player.pve_tier}.png"} alt="" class="w-5 h-5" loading="lazy" />
            <span class="text-sm text-faction-text font-medium"><%= GH.pve_tier_name(@current_player.pve_tier) %></span>
          </div>
          <div class="flex items-center gap-3 text-xs text-faction-text-muted">
            <.resource_counter value={@current_player.pvp_points || 0} icon="xp" />
          </div>
        </div>
      </div>

      <%!-- Current Hero Mini Panel --%>
      <div :if={@current_hero} class="px-3 py-3 border-t border-surface-border">
        <div class="text-xs text-faction-text-muted uppercase tracking-wide mb-2">Current Hero</div>
        <div class="flex items-center gap-2 mb-2">
          <.portrait_frame src={GH.image_url(@current_hero.avatar)} size="sm" />
          <div class="min-w-0">
            <div class="text-sm font-medium text-faction-text truncate"><%= @current_hero.avatar.name %></div>
            <div class="text-xs text-faction-text-muted">Lv. <%= @current_hero.level %></div>
          </div>
        </div>
        <div class="space-y-1">
          <.health_bar current={@current_hero.total_hp} max={max(@current_hero.total_hp, 1)} class="h-3 text-[10px]" />
          <.mana_bar current={@current_hero.total_mp} max={max(@current_hero.total_mp, 1)} class="h-3 text-[10px]" />
        </div>
        <div class="flex gap-1 mt-2">
          <.skill_icon :for={skill <- @current_hero.skills} skill={skill} size="sm" />
        </div>
      </div>
    </aside>
    """
  end

  # -------------------------------------------------------------------
  # Hero Panel (expanded, for detail views)
  # -------------------------------------------------------------------

  @doc """
  Renders an expanded hero panel with full stats, skills, items, and gold.
  """
  attr :hero, :map, required: true
  attr :class, :string, default: nil

  def hero_panel(assigns) do
    ~H"""
    <div class={["bg-surface border border-surface-border rounded", @class]}>
      <%!-- Header with avatar --%>
      <div class="flex items-center gap-3 p-4 border-b border-surface-border">
        <.portrait_frame src={GH.image_url(@hero.avatar)} size="md" />
        <div>
          <div class="text-gold font-semibold"><%= @hero.avatar.name %></div>
          <div class="text-sm text-faction-text-muted">Level <%= @hero.level %></div>
          <.league_badge tier={@hero.league_tier} show_name size="sm" />
        </div>
      </div>

      <%!-- HP / MP Bars --%>
      <div class="p-4 space-y-2">
        <.health_bar current={@hero.total_hp} max={max(@hero.total_hp, 1)} />
        <.mana_bar current={@hero.total_mp} max={max(@hero.total_mp, 1)} />
      </div>

      <%!-- Stats --%>
      <div class="px-4 pb-3">
        <.hero_stats hero={@hero} />
      </div>

      <%!-- Skills --%>
      <div class="px-4 pb-3">
        <div class="text-xs text-faction-text-muted uppercase tracking-wide mb-1.5">Skills</div>
        <div class="flex gap-2">
          <.skill_icon :for={skill <- @hero.skills} skill={skill} size="md" show_level />
        </div>
      </div>

      <%!-- Items --%>
      <div class="px-4 pb-3">
        <div class="text-xs text-faction-text-muted uppercase tracking-wide mb-1.5">Items</div>
        <div class="flex gap-1.5">
          <.item_slot :for={item <- sort_items(@hero.items)} item={item} size="md" />
        </div>
      </div>

      <%!-- Gold --%>
      <div class="px-4 pb-4">
        <.resource_counter value={@hero.gold} icon="gold" label="Gold" />
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp sort_items(items) when is_list(items), do: Enum.sort_by(items, fn item -> !item.active end)
  defp sort_items(_), do: []
end
