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

  def win_rate(user) do
    sum = user.pvp_wins + user.pvp_losses

    if sum > 0 do
      round(user.pvp_wins * 100 / sum)
    else
      0
    end
  end
end
