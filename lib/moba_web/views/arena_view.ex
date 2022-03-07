defmodule MobaWeb.ArenaView do
  use MobaWeb, :view

  alias Moba.Accounts

  def bot_timer(time) do
    time =
      Timex.parse!(time, "{ISO:Extended:Z}")
      |> Timex.format("{relative}", :relative)
      |> elem(1)

    "Your next opponent will be available #{time}"
  end

  def elite?(%{type: "elite_matchmaking"}), do: true
  def elite?(_), do: false

  def finished?(%{phase: "finished"}), do: true
  def finished?(_), do: false

  def match_label(%{type: "elite_matchmaking"}), do: "Elite"
  def match_label(_), do: "Normal"

  def match_result(match) do
    cond do
      match.phase != "finished" -> content_tag(:h5, "In Progress")
      is_nil(match.winner) -> content_tag(:h5, "Tie", class: "text-muted")
      match.winner_id == match.user_id -> content_tag(:h5, "Victory", class: "text-success")
      true -> content_tag(:h5, "Defeat", class: "text-danger")
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

  def replenish_time do
    match = Game.current_match()

    match &&
      match.inserted_at
      |> Timex.shift(days: +1)
      |> Timex.format("{relative}", :relative)
      |> elem(1)
  end
end
