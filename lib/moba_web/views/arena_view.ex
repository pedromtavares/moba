defmodule MobaWeb.ArenaView do
  use MobaWeb, :view

  def bot_timer(time) do
    time =
      Timex.parse!(time, "{ISO:Extended:Z}")
      |> Timex.format("{relative}", :relative)
      |> elem(1)

    "Your next opponent will be available #{time}"
  end

  def can_be_challenged?(%{last_challenge_at: nil}, _), do: true

  def can_be_challenged?(%{last_challenge_at: time}, current_time) do
    Timex.diff(Timex.shift(time, seconds: 30), current_time) < 0
  end

  def elite?(%{type: "elite_matchmaking"}), do: true
  def elite?(_), do: false

  def first_battle_for(%{id: duel_id, user_first_pick_id: hero_id}, battles), do: duel_battle(duel_id, hero_id, battles)

  def last_battle_for(%{id: duel_id, opponent_second_pick_id: hero_id}, battles),
    do: duel_battle(duel_id, hero_id, battles)

  def finished?(%{phase: "finished"}), do: true
  def finished?(_), do: false

  def duel_badge_class(%{type: type}) do
    case type do
      "pvp" -> "badge badge-light-danger"
      "elite_matchmaking" -> "badge badge-light-warning"
      _ -> "badge badge-light-primary"
    end
  end

  def duel_label(%{type: "elite_matchmaking"}), do: "Elite MM"
  def duel_label(%{type: "pvp"}), do: "Duel"
  def duel_label(_), do: "Normal MM"

  def duel_result(duel, user_id \\ nil) do
    user_id = user_id || duel.user_id

    cond do
      duel.phase != "finished" -> content_tag(:h5, "In Progress")
      is_nil(duel.winner) -> content_tag(:h5, "Tie", class: "text-white")
      duel.winner_id == user_id -> content_tag(:h5, "Victory", class: "text-success")
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

  def opponent_for(duel, %{id: id}) when duel.user_id == id, do: duel.opponent
  def opponent_for(duel, _), do: duel.user

  def rewards_badge(rewards) when rewards == 0, do: ""

  def rewards_badge(rewards) when rewards > 0 do
    content_tag("span", "+#{rewards} Season Points", class: "badge badge-pill badge-light-success")
  end

  def rewards_badge(rewards) do
    content_tag("span", "#{rewards} Season Points", class: "badge badge-pill badge-light-dark")
  end

  def season_rankings_string do
    Phoenix.View.render_to_string(MobaWeb.ArenaView, "_season_rankings.html", [])
  end

  def silenced?(%{current_user: %{status: "silenced"}}), do: true
  def silenced?(_), do: false

  def pvp?(%{type: "pvp"}), do: true
  def pvp?(_), do: false

  defp duel_battle(duel_id, hero_id, battles) do
    Enum.find(battles, &(&1.attacker_id == hero_id && &1.duel_id == duel_id))
  end
end
