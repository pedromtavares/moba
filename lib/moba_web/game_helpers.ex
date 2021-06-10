defmodule MobaWeb.GameHelpers do
  @moduledoc """
  Global utilities used by templates and views throughout the app
  """

  use Phoenix.HTML

  def image_url(%{"code" => "basic_attack"}), do: "/images/basic_attack.png"
  def image_url(%{code: "basic_attack"}), do: "/images/basic_attack.png"
  def image_url(%{code: "disarmed"}), do: "/images/disarmed.png"
  def image_url(%{code: "invulnerable"}), do: "/images/invulnerable.png"
  def image_url(%{image: image} = resource), do: get_url(image, resource)
  def image_url(%{"image" => image} = resource), do: get_url(image, resource)

  def background_url(%{background: background} = resource), do: get_background_url(background, resource)
  def background_url(%{"background" => background} = resource), do: get_background_url(background, resource)

  def hero_skill_list(%{active_build: %{skills: skills}}) do
    Enum.map(skills, fn skill ->
      img_tag(image_url(skill),
        data: [toggle: "tooltip"],
        title: skill_description(skill),
        class: "skill-img img-border-sm #{if skill.passive, do: "passive"} tooltip-mobile"
      )
    end)
  end

  def hero_item_list(hero, legacy \\ false)

  def hero_item_list(%{items: items}, false) do
    Moba.Game.sort_items(items)
    |> Enum.map(fn item ->
      image =
        img_tag(image_url(item),
          data: [toggle: "tooltip"],
          title: item_description(item),
          class: "item-img img-border-xs #{if !item.active, do: "passive"} tooltip-mobile"
        )

      content_tag(:div, image, class: "item-container col-4")
    end)
  end

  def hero_item_list(%{items: items}, true) do
    Moba.Game.sort_items(items)
    |> Enum.map(fn item ->
      img_tag(image_url(item),
        data: [toggle: "tooltip"],
        title: item_description(item),
        class: "item-img img-border-xs #{if !item.active, do: "passive"} tooltip-mobile"
      )
    end)
  end

  def hero_avatar(hero, show_medals \\ true) do
    tooltip = "Earn Medals by finishing in the top 3 of a match"
    medals = (show_medals && hero.user && hero.user.medal_count > 0 && "
      <p class='medals text-warning bg-light-dark d-none d-xl-block text-center' title='#{tooltip}' data-toggle='tooltip'>
          <i class='fa fa-medal mr-1'></i>#{hero.user.medal_count}
      </p>
    ") || nil

    "
    <div class='avatar-container'>
        <img src='#{image_url(hero.avatar)}' class='avatar img-border'/>
        #{medals}
    </div>
    "
    |> raw()
  end

  def hero_stats(hero, show_speed \\ false) do
    MobaWeb.HeroView.render("_stats.html", hero: hero, show_speed: show_speed)
  end

  def hero_stats_string(hero, show_speed \\ false) do
    Phoenix.View.render_to_string(MobaWeb.HeroView, "_stats.html", hero: hero, show_speed: show_speed)
  end

  def time_percentage(start, ending) do
    diff_ending = Timex.diff(start, ending, :minutes)
    diff_now = Timex.diff(start, Timex.now(), :minutes)
    diff_now * 100 / diff_ending
  end

  def pvp_win_rate(hero), do: Moba.Game.pvp_win_rate(hero)

  def pve_win_rate(hero), do: Moba.Game.pve_win_rate(hero)

  def formatted_effect(effect) do
    effect
    |> String.replace(~r/\n/, "<br/>")
    |> String.replace(~r/\[(?:armor)\](.+?)\[\/(?:armor)\]/, "<span class='text-warning'>\\1</span>")
    |> String.replace(~r/\[(?:damage)\](.+?)\[\/(?:damage)\]/, "<span class='text-danger'>\\1</span>")
    |> String.replace(~r/\[(?:power)\](.+?)\[\/(?:power)\]/, "<span class='text-pink'>\\1</span>")
    |> String.replace(~r/\[(?:hp)\](.+?)\[\/(?:hp)\]/, "<span class='text-success'>\\1</span>")
    |> String.replace(~r/\[(?:mp)\](.+?)\[\/(?:mp)\]/, "<span class='text-primary'>\\1</span>")
    |> String.replace(~r/\[(?:status)\](.+?)\[\/(?:status)\]/, "<span class='text-dark'>\\1</span>")
    |> String.replace(~r/\[(?:speed)\](.+?)\[\/(?:speed)\]/, "<span class='text-purple'>\\1</span>")
    |> raw
  end

  def skill_description(%{code: "basic_attack"} = skill) do
    "
    <h3>#{skill.name}</h3>

    #{skill.description}
    "
  end

  def skill_description(skill, full_description \\ true, show_name \\ true) do
    name = show_name && "<h3 class='mb-1'>#{skill.name}</h3>"
    level = full_description && skill.level && "<h5>Level #{skill.level}</h5>"
    full = (full_description && full_skill_description(skill)) || ""
    "
      #{name || ""}
      #{level || ""}
      <span class='text-dark'>#{skill.description}</span>
      #{full}
    "
  end

  def basic_attack_description do
    basic = Moba.basic_attack()
    "#{skill_description(basic)}<br/><br/>#{damage_type_description(basic)}"
  end

  def item_description(item) do
    {:safe, effects} = resource_effects(item)

    rarity =
      case item.rarity do
        "normal" -> "<span class='badge badge-light-dark'>Normal</span>"
        "rare" -> "<span class='badge badge-light-primary'>Rare</span>"
        "epic" -> "<span class='badge badge-light-purple'>Epic</span>"
        "legendary" -> "<span class='badge badge-light-danger'>Legendary</span>"
        _ -> ""
      end

    mp_cost =
      item.mp_cost && item.mp_cost > 0 &&
        "<span class='badge badge-light-primary'><i class='fa fa-flask mr-1'></i> #{item.mp_cost}</span>"

    cooldown =
      item.cooldown && item.cooldown > 0 &&
        "<span class='badge badge-light-warning'><i class='fa fa-clock mr-1'></i> #{item.cooldown}</span>"

    base_hp =
      item.base_hp && item.base_hp > 0 &&
        "<span class='badge badge-light-danger'><i class='fa fa-heart mr-1'></i> +#{item.base_hp} HP</span>"

    base_mp =
      item.base_mp && item.base_mp > 0 &&
        "<span class='badge badge-light-info'><i class='fa fa-flask mr-1'></i> +#{item.base_mp} MP</span>"

    base_atk =
      item.base_atk && item.base_atk > 0 &&
        "<span class='badge badge-light-success'><i class='fa fa-gavel mr-1'></i> +#{item.base_atk} ATK</span>"

    base_power =
      item.base_power && item.base_power > 0 &&
        "<span class='badge badge-light-pink'><i class='fa fa-bolt mr-1'></i> +#{item.base_power} Power</span>"

    base_armor =
      item.base_armor && item.base_armor > 0 &&
        "<span class='badge badge-light-warning'><i class='fa fa-shield mr-1'></i> +#{item.base_armor} Armor</span>"

    base_speed =
      item.base_speed && item.base_speed > 0 &&
        "<span class='badge badge-light-purple'><i class='fa fa-running mr-1'></i> +#{item.base_speed} Speed</span>"

    "
      <h3 class='mb-1'>#{item.name}</h3>
      <div class='text-center mb-1 mt-1'>#{rarity}</div>
      <span class='text-dark'>#{item.description}</span>
      <div class='text-center mb-2 mt-1'>
        #{base_hp || ""}
        #{base_mp || ""}
        #{base_atk || ""}
        #{base_power || ""}
        #{base_armor || ""}
        #{base_speed || ""}
      </div>
      <div class='text-center mb-2 mt-1'>
        #{mp_cost || ""}
        #{cooldown || ""}
      </div>
      #{effects}
    "
  end

  defp full_skill_description(skill) do
    {:safe, effects} = resource_effects(skill)

    damage_type = damage_type_description(skill)

    mp_cost =
      skill.mp_cost && skill.mp_cost > 0 &&
        "<span class='badge badge-light-primary'><i class='fa fa-flask mr-1'></i>#{skill.mp_cost}</span>"

    cooldown =
      skill.cooldown && skill.cooldown > 0 &&
        "<span class='badge badge-light-warning'><i class='fa fa-clock mr-1'></i>#{skill.cooldown}</span>"

    "
      <div class='text-center mb-2 mt-1'>
        #{mp_cost || ""}
        #{cooldown || ""}
        #{
          if skill.passive,
          do: "<span class='badge badge-light-dark'><i class='fa fa-dot-circle mr-1'></i>Passive</span>",
          else: ""
        }
        #{damage_type && "#{damage_type}<br/>"}
      </div>
      #{effects}
    "
  end

  defp damage_type_description(%{damage_type: damage_type}) do
    case damage_type do
      "normal" -> "<span class='badge badge-light-success'><i class='fa fa-bahai mr-1'></i>Normal Damage</span>"
      "pure" -> "<span class='badge badge-light-danger'><i class='fa fa-bahai mr-1'></i>Pure Damage</span>"
      "magic" -> "<span class='badge badge-light-purple'><i class='fa fa-bahai mr-1'></i>Magic Damage</span>"
      _ -> nil
    end
  end

  defp resource_effects(resource) do
    (resource.effects || "")
    |> String.replace("[base_damage]", "#{Map.get(resource, :base_damage)}")
    |> String.replace("[hp_multiplier]", (resource.hp_multiplier && "#{round(resource.hp_multiplier * 100)}") || "")
    |> String.replace(
      "[other_hp_multiplier]",
      (resource.other_hp_multiplier && "#{round(resource.other_hp_multiplier * 100)}") || ""
    )
    |> String.replace(
      "[hp_regen_multiplier]",
      (resource.hp_regen_multiplier && "#{round(resource.hp_regen_multiplier * 100)}") || ""
    )
    |> String.replace("[atk_multiplier]", (resource.atk_multiplier && "#{round(resource.atk_multiplier * 100)}") || "")
    |> String.replace(
      "[other_atk_multiplier]",
      (resource.other_atk_multiplier && "#{round(resource.other_atk_multiplier * 100)}") || ""
    )
    |> String.replace("[mp_multiplier]", (resource.mp_multiplier && "#{round(resource.mp_multiplier * 100)}") || "")
    |> String.replace(
      "[other_mp_multiplier]",
      (resource.other_mp_multiplier && "#{round(resource.other_mp_multiplier * 100)}") || ""
    )
    |> String.replace(
      "[mp_regen_multiplier]",
      (resource.mp_regen_multiplier && "#{round(resource.mp_regen_multiplier * 100)}") || ""
    )
    |> String.replace(
      "[extra_multiplier]",
      (resource.extra_multiplier && "#{round(resource.extra_multiplier * 100)}") || ""
    )
    |> String.replace("[base_amount]", "#{resource.base_amount}")
    |> String.replace("[armor_amount]", "#{resource.armor_amount}")
    |> String.replace("[power_amount]", "#{resource.power_amount}")
    |> String.replace("[extra_amount]", "#{resource.extra_amount}")
    |> String.replace("[roll_number]", "#{resource.roll_number}")
    |> String.replace("[mp_cost]", "#{resource.mp_cost}")
    |> formatted_effect()
  end

  # image field needs to be converted to a map of atoms due to serialization
  defp get_url(image, resource) do
    image =
      if image && Map.get(image, "file_name") do
        for {key, val} <- image, into: %{}, do: {String.to_atom(key), val}
      else
        image
      end

    Moba.Image.url({image, resource}, :original)
  end

  # image field needs to be converted to a map of atoms due to serialization
  defp get_background_url(background, resource) do
    background =
      if background && Map.get(background, "file_name") do
        for {key, val} <- background, into: %{}, do: {String.to_atom(key), val}
      else
        background
      end

    Moba.Background.url({background, resource}, :original)
  end
end
