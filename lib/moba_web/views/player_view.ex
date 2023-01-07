defmodule MobaWeb.PlayerView do
  use MobaWeb, :view
  alias MobaWeb.{ArenaView, DashboardView}

  defdelegate avatar_class(hero), to: DashboardView

  def daily_win_rate(%{daily_matches: matches, daily_wins: wins}) when matches > 0 do
    "#{round(wins / matches * 100)}%"
  end

  def daily_win_rate(_), do: "0%"

  def in_ranking?(ranking, %{id: id}) do
    ranking
    |> Enum.map(& &1.id)
    |> Enum.member?(id)
  end

  def opponent_for(duel, %{id: id}) when duel.player_id == id, do: duel.opponent_player
  def opponent_for(duel, _), do: duel.player

  def performance_class(%{daily_matches: matches}) when matches < 15, do: "text-orange"
  def performance_class(%{daily_matches: matches}) when matches < 30, do: "text-warning"
  def performance_class(_), do: "text-success"

  def registered_label(player) do
    time = if player.user, do: player.user.inserted_at, else: player.inserted_at
    formatted = time |> Timex.format("{relative}", :relative) |> elem(1)

    cond do
      player.bot_options -> "A.I. Player"
      player.user -> "Registered #{formatted}"
      true -> "Joined #{formatted}"
    end
  end

  def rewards_badge(rewards) when rewards == 0, do: ""

  def rewards_badge(rewards) when rewards > 0 do
    content_tag("span", "+#{rewards} Season Points", class: "badge badge-pill badge-light-success")
  end

  def rewards_badge(rewards) do
    content_tag("span", "#{rewards} Season Points", class: "badge badge-pill badge-light-dark")
  end

  def season_score(player) do
    1000 * player.best_immortal_streak + 500 * player.pve_tier + player.pvp_points
  end

  def shadow_rank(%{ranking: 1, pvp_tier: tier}), do: tier + 1
  def shadow_rank(%{pvp_tier: tier}), do: tier

  def total_win_rate(%{total_matches: matches, total_wins: wins}) when matches > 0 do
    "#{round(wins / matches * 100)}%"
  end

  def total_win_rate(_), do: "0%"
end
