defmodule MobaWeb.ArenaView do
  use MobaWeb, :view

  def bot_timer(time) do
    time =
      Timex.parse!(time, "{ISO:Extended:Z}")
      |> Timex.format("{relative}", :relative)
      |> elem(1)

    "Your next opponent will be available #{time}"
  end

  def elite?(%{type: "elite_matchmaking"}), do: true
  def elite?(_), do: false

  def first_battle_for(%{id: duel_id, user_first_pick: hero_id}, battles), do: duel_battle(duel_id, hero_id, battles)

  def last_battle_for(%{id: duel_id, opponent_second_pick: hero_id}, battles), do: duel_battle(duel_id, hero_id, battles)

  def finished?(%{phase: "finished"}), do: true
  def finished?(_), do: false

  def match_badge_class(%{type: type}) do
    case type do
      "pvp" -> "badge badge-light-danger"
      "elite_matchmaking" -> "badge badge-light-warning"
      _ -> "badge badge-light-primary"
    end
  end

  def match_label(%{type: "elite_matchmaking"}), do: "Elite MM"
  def match_label(%{type: "pvp"}), do: "Duel"
  def match_label(_), do: "Normal MM"

  def match_result(match) do
    cond do
      match.phase != "finished" -> content_tag(:h5, "In Progress")
      is_nil(match.winner) -> content_tag(:h5, "Tie", class: "text-white")
      match.winner_id == match.user_id -> content_tag(:h5, "Victory", class: "text-success")
      true -> content_tag(:h5, "Defeat", class: "text-muted")
    end
  end

  def next_pvp_tier_percentage(%{season_tier: current_tier, season_points: season_points}) do
    max = Accounts.season_points_for(current_tier + 1)
    season_points * 100 / max
  end

  def next_pvp_tier(%{season_tier: current_tier}) do
    cond do
      current_tier >= Moba.max_season_tier() -> nil
      true -> current_tier + 1
    end
  end

  defp duel_battle(duel_id, hero_id, battles) do
    Enum.find(battles, &(&1.attacker_id == hero_id && &1.duel_id == duel_id))
  end
end
