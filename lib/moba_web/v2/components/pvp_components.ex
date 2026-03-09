defmodule MobaWeb.V2.Components.PvpComponents do
  @moduledoc """
  Shared PvP components for v2 Arena, Duel, and Match screens.
  """
  use Phoenix.Component

  import MobaWeb.V2.Components.GameComponents,
    only: [hero_item_strip: 1, hero_skill_strip: 1, hero_stat_group: 1, league_badge: 1]

  alias MobaWeb.V2.Components.GameHelpers, as: GH

  attr :hero, :map, required: true
  attr :class, :string, default: nil
  attr :editable, :boolean, default: false
  attr :picked, :boolean, default: false
  slot :actions

  def pvp_hero_card(assigns) do
    ~H"""
    <div
      class={[
        "card hero-card mb-0 border",
        @picked && "picked-hero-card",
        @class
      ]}
      style={"background-image: url(#{GH.background_url(@hero)})"}
    >
      <div class="card-header pt-0 pb-1">
        <h4 class="font-17 text-white d-flex justify-content-between align-items-center mb-0">
          <span class="font-italic font-20 f-rpg">
            <%= if @hero.pve_ranking do %>
              {"##{@hero.pve_ranking}"}
            <% end %>
          </span>
          <div>
            <.league_badge tier={@hero.league_tier} variant="legacy" />
            {@hero.name}
          </div>
          <span class="font-15 font-italic" title={hero_stats_title(@hero)}>
            Level {@hero.level} {@hero.avatar.name}
          </span>
        </h4>
      </div>
      <div class="card-body text-center"></div>
      <div class="transparent card-footer p-0 text-center">
        <div class="row my-1">
          <div class="col justify-content-center d-flex">
            <.hero_stat_group hero={@hero} />
          </div>
        </div>
        <div class="row">
          <div class="col-12">
            <.hero_skill_strip skills={@hero.skills} />
            <.hero_item_strip items={sort_items(@hero.items)} />
          </div>
        </div>
      </div>
      <div :if={@actions != []} class="d-flex justify-content-between" style="background: #323b44 !important">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr :hero, :map, required: true
  attr :turn_hero, :map, required: true

  def turn_snapshot(assigns) do
    ~H"""
    <div class="row mt-1">
      <div class="col-4">
        <img src={GH.image_url(@hero.avatar)} class="avatar" />
      </div>
      <div class="col">
        <div class="row mt-1 mb-1">
          <div class="col">
            <div class="progress progress-fixed">
              <%= if @turn_hero.current_hp > 0 do %>
                <div
                  style={"width:#{health_pct(@turn_hero)}%"}
                  class="progress-bar bg-danger"
                >
                  <span>&nbsp;{@turn_hero.current_hp}&nbsp;</span>
                </div>
              <% else %>
                <div style="width:100%" class="progress-bar bg-dark">
                  <span>DEAD</span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        <div class="row">
          <div class="col">
            <div class="progress progress-fixed">
              <%= if @turn_hero.current_hp > 0 do %>
                <div
                  style={"width:#{mana_pct(@turn_hero)}%"}
                  class="progress-bar bg-primary"
                >
                  <span>&nbsp;{@turn_hero.current_mp}&nbsp;</span>
                </div>
              <% else %>
                <div style="width:100%" class="progress-bar bg-dark">
                  <span>0</span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp health_pct(%{current_hp: current_hp, total_hp: total_hp}) when total_hp > 0 do
    current_hp * 100 / total_hp
  end

  defp health_pct(_), do: 0

  defp mana_pct(%{current_mp: current_mp, total_mp: total_mp}) when total_mp > 0 do
    current_mp * 100 / total_mp
  end

  defp mana_pct(_), do: 0

  defp hero_stats_title(hero) do
    "HP: #{hero.total_hp} | MP: #{hero.total_mp} | ATK: #{hero.atk} | POW: #{hero.power} | ARM: #{hero.armor} | SPD: #{hero.speed}"
  end

  defp sort_items(items) when is_list(items), do: Moba.Game.sort_items(items)
  defp sort_items(_), do: []
end
