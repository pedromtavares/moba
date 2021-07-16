defmodule MobaWeb.JungleView do
  use MobaWeb, :view

  def streak_title(hero), do: MobaWeb.CurrentHeroView.bonus_xp_title(hero)

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

  def next_league_percentage(hero) do
    max = Moba.pve_points_limit()
    hero.pve_points * 100 / max
  end

  def next_league(%{league_tier: current_tier}) do
    cond do
      current_tier >= Moba.max_league_tier() -> nil
      true -> current_tier + 1
    end
  end

  def reward_badges_for(%{xp_boosted_battles_available: xp_boost} = hero, difficulty) do
    battle_xp = if xp_boost > 0, do: Moba.battle_xp() * 2, else: Moba.battle_xp()
    base_xp = round(battle_xp * Moba.xp_percentage(difficulty) / 100)
    double_xp = base_xp * 2

    xp_reward =
      if hero.level < Moba.max_hero_level() do
        content_tag(:span, "+#{double_xp}/+#{base_xp} XP", class: "badge badge-pill badge-light-primary mr-1")
      else
        ""
      end

    points =
      if Game.max_league?(hero) do
        ""
      else
        draw_points = Moba.tie_pve_points(difficulty)
        victory_points = Moba.victory_pve_points(difficulty)

        content_tag(:span, "+#{victory_points}/+#{draw_points} Points",
          class: "badge badge-pill badge-light-success mr-1"
        )
      end

    streak_xp = round(Moba.win_streak_xp(2) * Moba.streak_percentage(difficulty) / 100)

    safe_to_string(
      content_tag :div do
        [
          xp_reward,
          content_tag(:span, "+#{double_xp}/+#{base_xp} Gold", class: "badge badge-pill badge-light-warning mr-1"),
          points,
          content_tag(:span, "+#{streak_xp} XP/Gold per Undefeated Streak", class: "badge badge-pill badge-light-purple")
        ]
      end
    )
  end

  def boss_available?(hero) do
    hero.boss_id && Game.get_hero!(hero.boss_id)
  end

  def boss_percentage(boss) do
    boss.total_hp * 100 / boss.avatar.total_hp
  end

  def show_league_challenge?(%{pve_points: pve_points, league_tier: league_tier}) do
    pve_points >= Moba.pve_points_limit() && league_tier < Moba.master_league_tier()
  end

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
