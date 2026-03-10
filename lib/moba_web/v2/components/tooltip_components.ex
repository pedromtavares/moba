defmodule MobaWeb.V2.Components.TooltipComponents do
  @moduledoc """
  Bootstrap tooltip-body formatters for v2.

  These functions intentionally return HTML strings because the current
  tooltip integration still depends on `title` attributes.
  """

  alias MobaWeb.V2.Components.GameHelpers, as: GH

  def hero_stats_tooltip(hero, show_speed \\ false) do
    buttons =
      hero_stat_entries(hero, show_speed)
      |> Enum.map_join(&hero_stat_tooltip_button/1)

    "<div class='btn-group hero-stats'>#{buttons}</div>"
  end

  def hero_stats_string(hero, show_speed \\ false), do: hero_stats_tooltip(hero, show_speed)

  def skill_tooltip(%{code: "basic_attack"} = skill) do
    "<h3 class='text-center'>#{skill.name}</h3>#{skill.description}"
  end

  def skill_tooltip(skill, full_description \\ true, show_name \\ true) do
    name = show_name && "<h3 class='mb-1 text-center'>#{skill.name}</h3>"
    level = full_description && skill.level && "<h5 class='text-center'>Level #{skill.level}</h5>"
    full = full_description && full_skill_description_html(skill)

    "#{name || ""}#{level || ""}<span class='text-dark'>#{skill.description}</span><div class='text-center'>#{full || ""}</div>"
  end

  def basic_attack_tooltip do
    basic = Moba.basic_attack()
    "#{skill_tooltip(basic)}<br/><br/>#{damage_type_html(basic.damage_type) || ""}"
  end

  def item_tooltip(item) do
    info = GH.item_info(item)
    effects = formatted_effect_html(info.effects)

    rarity =
      case info.rarity do
        "normal" -> "<span class='badge badge-light-dark'>Normal</span>"
        "rare" -> "<span class='badge badge-light-primary'>Rare</span>"
        "epic" -> "<span class='badge badge-light-purple'>Epic</span>"
        "legendary" -> "<span class='badge badge-light-danger'>Legendary</span>"
        _ -> ""
      end

    "
      <h3 class='mb-1 text-center'>#{info.name}</h3>
      <div class='text-center mb-1 mt-1'>#{rarity}</div>
      <span class='text-dark'>#{info.description}</span>
      <div class='text-center mb-2 mt-1'>
        #{stat_badge(:hp, info.stats)}
        #{stat_badge(:mp, info.stats)}
        #{stat_badge(:atk, info.stats)}
        #{stat_badge(:power, info.stats)}
        #{stat_badge(:armor, info.stats)}
        #{stat_badge(:speed, info.stats)}
      </div>
      <div class='text-center mb-2 mt-1'>
        #{mp_cost_badge(info.mp_cost)}
        #{cooldown_badge(info.cooldown)}
      </div>
      <div class='text-center'>#{effects}</div>
    "
  end

  def formatted_effect_tooltip(effect) when is_binary(effect), do: formatted_effect_html(effect)
  def formatted_effect_tooltip(_), do: ""

  def effect_tooltip(%{name: name, description: description}) do
    "<h3>#{name}</h3>#{description}"
  end

  defp hero_stat_entries(hero, show_speed) do
    stats = [
      {"Health", "btn btn-icon waves-effect btn-outline-dark text-danger", "fa fa-heart mr-1", hero.total_hp + hero.item_hp},
      {"Energy", "btn btn-icon waves-effect waves-light btn-outline-dark text-info", "fa fa-bolt", hero.total_mp + hero.item_mp},
      {"Attack", "btn btn-icon waves-effect waves-light btn-outline-dark text-success", "fa fa-dagger", hero.atk + hero.item_atk},
      {"Power", "btn btn-icon waves-effect waves-light btn-outline-dark text-pink", "fa fa-galaxy", hero.power + hero.item_power},
      {"Armor", "btn btn-icon waves-effect waves-light btn-outline-dark text-warning", "fa fa-shield-halved", hero.armor + hero.item_armor}
    ]

    if show_speed do
      stats ++ [{"Speed", "btn btn-icon waves-effect waves-light btn-outline-dark text-orange", "fa fa-running", hero.speed + hero.item_speed}]
    else
      stats
    end
  end

  defp hero_stat_tooltip_button({title, class_name, icon, value}) do
    "<button class='#{class_name}' data-toggle='tooltip' title='#{title}'><i class='#{icon}'></i> #{value}</button>"
  end

  defp full_skill_description_html(skill) do
    info = GH.skill_info(skill)
    effects = formatted_effect_html(info.effects)
    damage_type = damage_type_html(info.damage_type)

    "
      <div class='text-center mb-2 mt-1'>
        #{mp_cost_badge(info.mp_cost)}
        #{cooldown_badge(info.cooldown)}
        #{passive_badge(info.passive)}
        #{if damage_type, do: "#{damage_type}<br/>", else: ""}
      </div>
      #{effects}
    "
  end

  defp damage_type_html("normal"), do: "<span class='badge badge-light-success'><i class='fa fa-bahai mr-1'></i>Normal Damage</span>"
  defp damage_type_html("pure"), do: "<span class='badge badge-light-danger'><i class='fa fa-bahai mr-1'></i>Pure Damage</span>"
  defp damage_type_html("magic"), do: "<span class='badge badge-light-purple'><i class='fa fa-bahai mr-1'></i>Magic Damage</span>"
  defp damage_type_html(_), do: nil

  defp mp_cost_badge(nil), do: ""
  defp mp_cost_badge(cost), do: "<span class='badge badge-light-primary'><i class='fa fa-bolt mr-1'></i>#{cost}</span>"

  defp cooldown_badge(nil), do: ""
  defp cooldown_badge(cooldown), do: "<span class='badge badge-light-warning'><i class='fa fa-clock mr-1'></i>#{cooldown}</span>"

  defp passive_badge(true), do: "<span class='badge badge-light-dark'><i class='fa fa-dot-circle mr-1'></i>Passive</span>"
  defp passive_badge(false), do: ""

  defp stat_badge(key, stats) do
    case List.keyfind(stats, key, 0) do
      {_, value} -> stat_badge_html(key, value)
      nil -> ""
    end
  end

  defp stat_badge_html(:hp, value), do: "<span class='badge badge-light-danger'><i class='fa fa-heart mr-1'></i> +#{value} Health</span>"
  defp stat_badge_html(:mp, value), do: "<span class='badge badge-light-info'><i class='fa fa-bolt mr-1'></i> +#{value} Energy</span>"
  defp stat_badge_html(:atk, value), do: "<span class='badge badge-light-success'><i class='fa fa-dagger mr-1'></i> +#{value} Attack</span>"
  defp stat_badge_html(:power, value), do: "<span class='badge badge-light-pink'><i class='fa fa-galaxy mr-1'></i> +#{value} Power</span>"
  defp stat_badge_html(:armor, value), do: "<span class='badge badge-light-warning'><i class='fa fa-shield-halved mr-1'></i> +#{value} Armor</span>"
  defp stat_badge_html(:speed, value), do: "<span class='badge badge-light-purple'><i class='fa fa-running mr-1'></i> +#{value} Speed</span>"

  defp formatted_effect_html(effect) when is_binary(effect) do
    effect
    |> String.replace(~r/\n/, "<br/>")
    |> String.replace(~r/\[(?:armor)\](.+?)\[\/(?:armor)\]/, "<span class='text-warning'>\\1</span>")
    |> String.replace(~r/\[(?:damage)\](.+?)\[\/(?:damage)\]/, "<span class='text-danger'>\\1</span>")
    |> String.replace(~r/\[(?:power)\](.+?)\[\/(?:power)\]/, "<span class='text-pink'>\\1</span>")
    |> String.replace(~r/\[(?:hp)\](.+?)\[\/(?:hp)\]/, "<span class='text-success'>\\1</span>")
    |> String.replace(~r/\[(?:mp)\](.+?)\[\/(?:mp)\]/, "<span class='text-primary'>\\1</span>")
    |> String.replace(~r/\[(?:status)\](.+?)\[\/(?:status)\]/, "<span class='text-dark'>\\1</span>")
    |> String.replace(~r/\[(?:speed)\](.+?)\[\/(?:speed)\]/, "<span class='text-purple'>\\1</span>")
  end

  defp formatted_effect_html(_), do: ""
end
