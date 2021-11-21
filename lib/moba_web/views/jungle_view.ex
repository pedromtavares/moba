defmodule MobaWeb.JungleView do
  use MobaWeb, :view

  def boss_available?(hero) do
    hero.boss_id && Game.get_hero!(hero.boss_id)
  end

  def boss_percentage(boss) do
    boss.total_hp * 100 / boss.avatar.total_hp
  end

  def difficulty_color(difficulty) do
    case difficulty do
      "weak" -> "success"
      "moderate" -> "primary"
      "strong" -> "danger"
      _ -> "dark"
    end
  end

  def difficulty_label(difficulty) do
    case difficulty do
      "weak" -> "Easy"
      "moderate" -> "Medium"
      "strong" -> "Hard"
      _ -> "??"
    end
  end

  def difficulty_reward_label(difficulty) do
    number =
      case difficulty do
        "weak" -> 1
        "moderate" -> 2
        "strong" -> 3
        _ -> 0
      end

    coins =
      Enum.reduce(1..number, "", fn _n, acc ->
        acc <> "<i class='fa fa-coins'></i>"
      end)

    raw(coins)
  end

  def offense_percentage(target, targets) do
    heroes = Enum.map(targets, & &1.defender)
    with_stats = Enum.map(heroes, &with_display_stats(&1, heroes))
    max = Enum.max_by(with_stats, fn hero -> hero.display_offense end) || target.defender

    if max.display_offense && max.display_offense > 0 do
      with_display_stats(target.defender, heroes).display_offense * 100 / max.display_offense
    else
      100
    end
  end

  def defense_percentage(target, targets) do
    heroes = Enum.map(targets, & &1.defender)
    with_stats = Enum.map(heroes, &with_display_stats(&1, heroes))
    max = Enum.max_by(with_stats, fn hero -> hero.display_defense end) || target.defender

    if max.display_defense && max.display_defense > 0 do
      max.display_defense && with_display_stats(target.defender, heroes).display_defense * 100 / max.display_defense
    else
      100
    end
  end

  def next_league(%{league_tier: current_tier}) do
    cond do
      current_tier + 1 >= Moba.max_league_tier() -> nil
      true -> current_tier + 1
    end
  end

  def reward_badges_for(hero, difficulty) do
    base_xp = round(Moba.battle_xp() * Moba.xp_percentage(difficulty, hero.easy_mode) / 100)
    double_xp = base_xp * 2

    xp_reward =
      if hero.level < Moba.max_hero_level() do
        content_tag(:span, "+#{double_xp}/+#{base_xp} XP", class: "badge badge-pill badge-light-primary mr-1")
      else
        ""
      end

    safe_to_string(
      content_tag :div do
        [
          xp_reward,
          content_tag(:span, "+#{double_xp}/+#{base_xp} Gold", class: "badge badge-pill badge-light-warning mr-1")
        ]
      end
    )
  end

  def pve_tier_title(%{pve_tier: 1}), do: "Season Novice"
  def pve_tier_title(%{pve_tier: 2}), do: "Season Adept"
  def pve_tier_title(%{pve_tier: 3}), do: "Season Veteran"
  def pve_tier_title(%{pve_tier: 4}), do: "Season Expert"

  def pve_tier_bonuses(%{pve_tier: tier}) do
    base = pve_tier_bonus_html("Starting gold: +1200 (800 -> 2000)")
    base = if tier > 1, do: "#{base}#{pve_tier_bonus_html("50% discount on buybacks")}", else: base

    base =
      if tier > 2, do: "#{base}#{pve_tier_bonus_html("Gank is reimbursed on death (+1 available Ganks)")}", else: base

    base = if tier > 3, do: "#{base}#{pve_tier_bonus_html("Ability to refresh Targets up to 5 times")}", else: base

    raw(base)
  end

  def show_league_challenge?(%{pve_battles_available: 0, league_tier: league_tier}) do
    league_tier < Moba.master_league_tier()
  end

  def show_league_challenge?(_), do: false

  defp pve_tier_bonus_html(label), do: "<div class='my-1'><i class='fa fa-hand-point-right mr-1'></i>#{label}</div>"

  defp with_display_stats(hero, heroes) do
    minimum = minimum_stats(heroes)
    units = Moba.avatar_stat_units()

    Map.merge(hero, %{
      display_defense:
        (total_hp(hero) - minimum[:total_hp]) / units[:total_hp] + (total_armor(hero) - minimum[:armor]) / units[:armor],
      display_offense:
        (total_atk(hero) - minimum[:atk]) / units[:atk] + (total_power(hero) - minimum[:power]) / units[:power]
    })
  end

  defp minimum_stats(heroes) do
    %{
      atk: Enum.min_by(heroes, fn hero -> total_atk(hero) end) |> total_atk(),
      total_hp: Enum.min_by(heroes, fn hero -> total_hp(hero) end) |> total_hp(),
      armor: Enum.min_by(heroes, fn hero -> total_armor(hero) end) |> total_armor(),
      power: Enum.min_by(heroes, fn hero -> total_power(hero) end) |> total_power()
    }
  end

  defp total_hp(hero), do: hero.total_hp + hero.item_hp
  defp total_atk(hero), do: hero.atk + hero.item_atk
  defp total_armor(hero), do: hero.armor + hero.item_armor
  defp total_power(hero), do: hero.power + hero.item_power
end
