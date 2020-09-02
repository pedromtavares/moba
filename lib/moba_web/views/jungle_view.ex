defmodule MobaWeb.JungleView do
  use MobaWeb, :view

  alias Moba.Game
  alias MobaWeb.{GameView, HeroView}

  def difficulty_color(difficulty) do
    case difficulty do
      "weak" -> "success"
      "moderate" -> "primary"
      "strong" -> "danger"
      _ -> "dark"
    end
  end

  def weak(targets), do: filter_targets(targets, "weak")
  def moderate(targets), do: filter_targets(targets, "moderate")
  def strong(targets), do: filter_targets(targets, "strong")

  def next_league_percentage(hero) do
    max = Moba.pve_points_limit()
    hero.pve_points * 100 / max
  end

  def next_league(%{league_tier: current_tier}) do
    cond do
      current_tier == Moba.max_league_tier() -> nil
      true -> current_tier + 1
    end
  end

  def can_create_new_hero?(user), do: Game.can_create_new_hero?(user)

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

    content_tag :div do
      [
        xp_reward,
        content_tag(:span, "+#{double_xp}/+#{base_xp} Gold", class: "badge badge-pill badge-light-warning mr-1"),
        points,
        content_tag(:span, "+#{streak_xp} XP/Gold per Win Streak", class: "badge badge-pill badge-light-purple")
      ]
    end
  end

  def streak_title(hero), do: HeroView.bonus_xp_title(hero)

  def next_match_description, do: HeroView.next_match_description()

  defp filter_targets(targets, difficulty), do: Enum.filter(targets, fn target -> target.difficulty == difficulty end)
end
