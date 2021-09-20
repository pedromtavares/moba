defmodule MobaWeb.UserView do
  use MobaWeb, :view
  alias Moba.Game

  def win_rate(%Game.Schema.ArenaPick{} = pick) do
    sum = pick.wins + pick.losses

    if sum > 0 do
      round(pick.wins * 100 / sum)
    else
      0
    end
  end

  def win_rate(%{duel_count: count, duel_wins: wins}) do
    if count > 0 do
      round(wins * 100 / count)
    else
      0
    end
  end
end
