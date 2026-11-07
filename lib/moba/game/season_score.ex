defmodule Moba.Game.SeasonScore do
  @moduledoc "Season standings combine Training Rank, Arena Rating, best streak, and the current Immortal title."
  import Ecto.Query, only: [dynamic: 2]

  @immortal_bonus 200

  def total(player),
    do: training_points(player) + (player.pvp_points || 0) + streak_points(player) + immortal_bonus(player)

  def training_points(%{pve_tier: tier}), do: (tier || 0) * 100
  def streak_points(%{best_immortal_streak: streak}), do: (streak || 0) * 20
  def immortal_bonus(player), do: if(immortal?(player), do: @immortal_bonus, else: 0)
  def immortal?(%{pvp_tier: 2, ranking: 1}), do: true
  def immortal?(_), do: false

  # Use the same expression wherever records are sorted or exported, including nullable historical data.
  def expression do
    dynamic(
      [player],
      coalesce(player.pve_tier, 0) * 100 + coalesce(player.pvp_points, 0) +
        coalesce(player.best_immortal_streak, 0) * 20 +
        fragment("CASE WHEN ? = 2 AND ? = 1 THEN 200 ELSE 0 END", player.pvp_tier, player.ranking)
    )
  end
end
