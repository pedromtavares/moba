defmodule MobaWeb.MatchView do
  use MobaWeb, :view

  def rewards_for(ranking) do
    number = round(3 / ranking)

    medals =
      Enum.reduce(1..number, "", fn _n, acc ->
        acc <> "<i class='fa fa-medal'></i>"
      end)

    shards =
      Enum.reduce(1..number, "", fn _n, acc ->
        acc <> "<i class='fab fa-ethereum'></i>"
      end)

    raw(medals <> "" <> shards)
  end

  def next_medal(%{season_tier: current_tier}) do
    cond do
      current_tier >= Moba.max_season_tier() -> nil
      true -> current_tier + 1
    end
  end

  def current_points_percentage(%{user: user} = hero) do
    current = user.season_points - hero.pvp_points
    current = if current < 0, do: 0, else: current
    current * 100 / next_medal_points(user)
  end

  def next_medal_percentage(%{user: user} = hero) do
    hero.pvp_points * 100 / next_medal_points(user)
  end

  def next_medal_points(user) do
    next = next_medal(user)

    Moba.Accounts.season_points_for(next)
  end

end
