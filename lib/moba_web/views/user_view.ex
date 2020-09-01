defmodule MobaWeb.UserView do
  use MobaWeb, :view

  def win_rate(user) do
    sum = user.pvp_wins + user.pvp_losses

    if sum > 0 do
      round(user.pvp_wins * 100 / sum)
    else
      0
    end
  end
end
