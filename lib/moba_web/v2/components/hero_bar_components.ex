defmodule MobaWeb.V2.Components.HeroBarComponents do
  use Phoenix.Component

  import MobaWeb.V2.Components.GameComponents, only: [hero_stat_group: 1]

  alias Moba.Game
  alias MobaWeb.V2.Components.GameHelpers, as: GH
  alias MobaWeb.V2.ShopComponent
  alias MobaWeb.V2.Components.TooltipComponents, as: TT

  embed_templates "hero_bar_components/*"

  attr :current_hero, :map, required: true
  attr :editing, :boolean, required: true
  attr :show_build, :boolean, required: true
  attr :show_shop, :boolean, required: true
  attr :tutorial_step, :integer, required: true
  attr :event_target, :any, default: nil

  def hero_bar(assigns) do
    hero_bar_template(assigns)
  end

  attr :current_hero, :map, required: true

  def hero_bar_stats(assigns) do
    ~H"""
    <.hero_stat_group hero={@current_hero} tooltip_mode="detailed" variant="hero_bar" />
    """
  end

  def target_attrs(nil), do: %{}
  def target_attrs(target), do: %{"phx-target" => target}

  def edit_orders_label(%{finished_at: finished_at}) when is_nil(finished_at) do
    "Click to edit the skill and item orders that will be preselected so you don't have to manually select them in every battle."
  end

  def edit_orders_label(_) do
    "Click to edit the skill and item orders that will be used when defending against other players in the Arena."
  end

  def sorted_items(%{items: items}), do: Game.sort_items(items)
  def sorted_skills(%{skills: skills}), do: Enum.sort_by(skills, &{&1.ultimate, &1.passive, &1.name})
  def can_level_skill?(hero, skill), do: Game.can_level_skill?(hero, skill)
  def max_skill_level(skill), do: Game.max_skill_level(skill)
  def xp_percentage(hero), do: hero.experience * 100 / xp_to_next_level(hero)
  def xp_to_next_level(hero), do: Game.xp_to_next_hero_level(hero.level + 1)

  def next_skill_description(skill) do
    next = Game.get_current_skill!(skill.code, skill.level + 1)

    "#{TT.skill_tooltip(skill)}<hr/>#{TT.skill_tooltip(%{next | name: "Next Level (#{next.level})", level: nil, description: ""})}"
  end
end
