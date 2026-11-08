defmodule MobaWeb.V2.Components.TooltipComponents do
  @moduledoc """
  Bootstrap tooltip-body formatters for v2.

  These functions intentionally return HTML strings because the current
  tooltip integration still depends on `title` attributes.
  """

  def hero_stats_tooltip(hero, show_speed \\ false) do
    buttons =
      hero_stat_entries(hero, show_speed)
      |> Enum.map_join(&hero_stat_tooltip_button/1)

    "<div class='btn-group hero-stats'>#{buttons}</div>"
  end

  def hero_stats_string(hero, show_speed \\ false), do: hero_stats_tooltip(hero, show_speed)

  def season_score_tooltip(player), do: MobaWeb.V2.Components.SeasonScoreTooltip.render(player)

  def arena_stats_tooltip(hero, player, battles \\ []) do
    hero
    |> MobaWeb.V2.Components.GameHelpers.match_hero_stats(player, battles)
    |> combat_stats_markup()
  end

  def combat_stats_tooltip(hero) do
    hero
    |> MobaWeb.V2.Components.GameHelpers.hero_stats()
    |> combat_stats_markup()
  end

  defp combat_stats_markup(stats) do
    rows =
      for {label, key, icon, tone} <- [
            {"Health", :hp, "heart", "danger"},
            {"Energy", :mp, "bolt", "info"},
            {"Attack", :atk, "dagger", "success"},
            {"Power", :power, "vortex", "pink"},
            {"Armor", :armor, "shield", "warning"},
            {"Speed", :speed, "runner", "orange"}
          ] do
        "<div class='arena-tooltip-stat text-#{tone}' data-stat='#{key}'><i class='ui-icon ui-#{icon}' aria-hidden='true'></i><span>#{label}</span><strong>#{stats[key]}</strong></div>"
      end

    "<div class='arena-stats-tooltip'><div>#{Enum.join(rows)}</div></div>"
  end

  def skill_tooltip(skill, full_description \\ true, show_name \\ true) do
    MobaWeb.V2.Components.SkillTooltip.render(skill, full: full_description, show_name: show_name)
  end

  def skill_upgrade_tooltip(skill, next), do: MobaWeb.V2.Components.SkillTooltip.render(skill, next: next)
  def skill_details(skill), do: MobaWeb.V2.Components.SkillTooltip.render(skill, details_only: true)
  def basic_attack_tooltip, do: skill_tooltip(Moba.basic_attack())

  def item_tooltip(item), do: MobaWeb.V2.Components.ItemTooltip.render(item)

  def formatted_effect_tooltip(effect) when is_binary(effect), do: formatted_effect_html(effect)
  def formatted_effect_tooltip(_), do: ""

  def effect_tooltip(%{name: name, description: description}) do
    "<h3>#{name}</h3>#{description}"
  end

  defp hero_stat_entries(hero, show_speed) do
    stats = [
      {"Health", "btn btn-icon waves-effect btn-outline-dark text-danger", "ui-icon ui-heart mr-1",
       hero.total_hp + hero.item_hp},
      {"Energy", "btn btn-icon waves-effect waves-light btn-outline-dark text-info", "ui-icon ui-bolt",
       hero.total_mp + hero.item_mp},
      {"Attack", "btn btn-icon waves-effect waves-light btn-outline-dark text-success", "ui-icon ui-dagger",
       hero.atk + hero.item_atk},
      {"Power", "btn btn-icon waves-effect waves-light btn-outline-dark text-pink", "ui-icon ui-vortex",
       hero.power + hero.item_power},
      {"Armor", "btn btn-icon waves-effect waves-light btn-outline-dark text-warning", "ui-icon ui-shield",
       hero.armor + hero.item_armor}
    ]

    if show_speed do
      stats ++
        [
          {"Speed", "btn btn-icon waves-effect waves-light btn-outline-dark text-orange", "ui-icon ui-runner",
           hero.speed + hero.item_speed}
        ]
    else
      stats
    end
  end

  defp hero_stat_tooltip_button({title, class_name, icon, value}) do
    "<span class='game-stat #{class_name}' title='#{title}'><i class='#{icon}' aria-hidden='true'></i> <span class='stat-value'>#{value}</span></span>"
  end

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
