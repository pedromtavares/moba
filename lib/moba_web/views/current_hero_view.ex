defmodule MobaWeb.CurrentHeroView do
  use MobaWeb, :view

  def sorted_items(%{items: items}), do: Game.sort_items(items)

  def sorted_skills(%{active_build: %{skills: skills}}), do: Enum.sort_by(skills, &{&1.ultimate, &1.passive, &1.name})

  def can_level_skill?(hero, skill), do: Game.can_level_skill?(hero, skill)

  def max_skill_level(skill), do: Game.max_skill_level(skill)

  def xp_percentage(hero), do: hero.experience * 100 / xp_to_next_level(hero)

  def xp_to_next_level(hero), do: Moba.xp_to_next_hero_level(hero.level + 1)

  def next_skill_description(skill) do
    next = Game.get_current_skill!(skill.code, skill.level + 1)

    "#{GH.skill_description(skill)}<hr/>#{GH.skill_description(%{next | name: "Next Level (#{next.level})", level: nil, description: ""})}"
  end

  def total_hp_description(hero) do
    title = "Total HP: #{hero.total_hp + hero.item_hp}"
    sub = "Your total Hit Points. When they reach 0 in a battle, you die and are defeated, with no rewards given."

    main =
      "Current base HP: #{hero.total_hp} <br/>HP given by items: #{hero.item_hp}<br/><br/>HP gain on level up: #{hero.avatar.hp_per_level}"

    attribute_description(title, sub, main)
  end

  def total_mp_description(hero) do
    title = "Total MP: #{hero.total_mp + hero.item_mp}"

    sub =
      "Your total Mana Points. Your 'fuel' in a battle, used to power abilities and active items. When they reach 0 in a battle, you will hit with a Basic Attack, which deals 100% ATK as Normal Damage."

    main =
      "Current base MP: #{hero.total_mp} <br/>MP given by items: #{hero.item_mp}<br/><br/>MP gain on level up: #{hero.avatar.mp_per_level}"

    attribute_description(title, sub, main)
  end

  def total_atk_description(hero) do
    title = "ATK: #{hero.atk + hero.item_atk}"
    sub = "Your total Attack (ATK). This is the base stat used to calculate damage in most skills and items."

    main =
      "Current ATK: #{hero.atk} <br/>ATK given by items: #{hero.item_atk}<br/><br/>ATK gain on level up: #{hero.avatar.atk_per_level}"

    attribute_description(title, sub, main)
  end

  def total_power_description(hero) do
    title = "Power: #{hero.power + hero.item_power}"

    sub =
      "Your total Power. Amplifies your total damage output and regeneration in a turn by 1% for every point in Power. E.g. 10 Power will give you 10% amplification."

    main = "Current Power: #{hero.power} <br/>Power given by items: #{hero.item_power}"
    attribute_description(title, sub, main)
  end

  def total_armor_description(hero) do
    title = "Armor: #{hero.armor + hero.item_armor}"

    sub =
      "Your total Armor. Reduces the total damage input you take on a defending turn, applied after the amplification from the opponent's Power. Each point of Armor will give 1% of damage reduction before 25 points, 0.5% after 25 points and 0.1% after 50 points. E.g. 150 Armor will give 47.5% reduction."

    main = "Current base Armor: #{hero.armor} <br/>Armor given by items: #{hero.item_armor}"
    attribute_description(title, sub, main)
  end

  def total_speed_description(hero) do
    title = "Speed: #{hero.speed + hero.item_speed}"

    sub =
      "Your total Speed. Each point in Speed gives you 1% chance to initiate a battle. E.g. 50 Speed will give you 50% chance to initiate. Speed only applies to whom is attacking."

    main = "Current base Speed: #{hero.speed} <br/>Speed given by items: #{hero.item_speed}"
    attribute_description(title, sub, main)
  end

  def attribute_description(title, sub, main) do
    "
      <h3 class='mb-1 text-center'>#{title}</h3>
      <span class='text-dark'>#{sub}</span>
      <div class='text-center mt-1'>
        #{main}
      </div>
    "
  end
end
