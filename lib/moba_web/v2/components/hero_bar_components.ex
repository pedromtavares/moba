defmodule MobaWeb.V2.Components.HeroBarComponents do
  use Phoenix.Component

  alias Moba.Game
  alias MobaWeb.V2.Components.GameHelpers, as: GH
  alias MobaWeb.V2.ShopComponent

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
    <div class="btn-group stats-group f-rpg">
      <button
        class="btn btn-icon btn-outline-dark text-danger tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_hp_description(@current_hero)}
      >
        <i class="fa fa-heart mr-1"></i> {@current_hero.total_hp + @current_hero.item_hp}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-info tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_mp_description(@current_hero)}
      >
        <i class="fa fa-bolt"></i> {@current_hero.total_mp + @current_hero.item_mp}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-success tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_atk_description(@current_hero)}
      >
        <i class="fa fa-dagger"></i> {@current_hero.atk + @current_hero.item_atk}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-pink tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_power_description(@current_hero)}
      >
        <i class="fa fa-galaxy"></i> {@current_hero.power + @current_hero.item_power}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-warning tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_armor_description(@current_hero)}
      >
        <i class="fa fa-shield-halved"></i> {@current_hero.armor + @current_hero.item_armor}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-orange tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_speed_description(@current_hero)}
      >
        <i class="fa fa-running"></i> {@current_hero.speed + @current_hero.item_speed}
      </button>
    </div>
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

    "#{GH.skill_description(skill)}<hr/>#{GH.skill_description(%{next | name: "Next Level (#{next.level})", level: nil, description: ""})}"
  end

  def total_hp_description(hero) do
    title = "Health: #{hero.total_hp + hero.item_hp}"
    sub = "Main survival stat. When it reaches 0 in a battle, you die and receive no rewards."

    main =
      "Current base Health: #{hero.total_hp} <br/>Health given by items: #{hero.item_hp}<br/><br/>Health gain on level up: #{hero.avatar.hp_per_level}"

    attribute_description(title, sub, main)
  end

  def total_mp_description(hero) do
    title = "Energy: #{hero.total_mp + hero.item_mp}"

    sub =
      "Main spending stat, used to power abilities and active items. When it reaches 0 in a battle, you will hit with a Basic Attack, which deals 100% Attack as Normal Damage."

    main =
      "Current base Energy: #{hero.total_mp} <br/>Energy given by items: #{hero.item_mp}<br/><br/>Energy gain on level up: #{hero.avatar.mp_per_level}"

    attribute_description(title, sub, main)
  end

  def total_atk_description(hero) do
    title = "Attack: #{hero.atk + hero.item_atk}"
    sub = "Base stat used to calculate damage in most skills and items."

    main =
      "Current Attack: #{hero.atk} <br/>Attack given by items: #{hero.item_atk}<br/><br/>Attack gain on level up: #{hero.avatar.atk_per_level}"

    attribute_description(title, sub, main)
  end

  def total_power_description(hero) do
    title = "Power: #{hero.power + hero.item_power}"

    sub =
      "Amplifies your total damage output and regeneration in a turn by 1% for every point in Power. E.g. 10 Power will give you 10% amplification."

    main = "Current Power: #{hero.power} <br/>Power given by items: #{hero.item_power}"
    attribute_description(title, sub, main)
  end

  def total_armor_description(hero) do
    title = "Armor: #{hero.armor + hero.item_armor}"

    sub =
      "Reduces the total damage you take on a defending turn, applied after the amplification from the opponent's Power. Each point of Armor will give 1% of damage reduction, with a maximum of 90%."

    main = "Current base Armor: #{hero.armor} <br/>Armor given by items: #{hero.item_armor}"

    attribute_description(title, sub, main)
  end

  def total_speed_description(hero) do
    title = "Speed: #{hero.speed + hero.item_speed}"

    sub =
      "Each point in Speed gives you 1% chance to initiate a battle. E.g. 50 Speed will give you 50% chance to initiate. When defending, each point in Speed over 100 gives you 1% chance to Evade the next non-ultimate normal damage attack. Evade costs no Energy and has a 2 turn cooldown. E.g. 120 Speed will give you 20% chance to Evade."

    main = "Current base Speed: #{hero.speed} <br/>Speed given by items: #{hero.item_speed}"

    attribute_description(title, sub, main)
  end

  defp attribute_description(title, sub, main) do
    "
      <h3 class='mb-1 text-center'>#{title}</h3>
      <span class='text-dark'>#{sub}</span>
      <div class='text-center mt-1'>
        #{main}
      </div>
    "
  end
end
