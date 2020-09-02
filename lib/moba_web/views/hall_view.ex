defmodule MobaWeb.HallView do
  use MobaWeb, :view

  def xp_percentage(user) do
    user.experience * 100 / Moba.user_level_xp()
  end

  def matches_left_on_ranking(hero) do
    full_time = hero.inserted_at |> Timex.shift(days: +7)
    days = Timex.diff(full_time, Timex.now(), :days)

    if days > 1 do
      "#{days} matches left"
    else
      "One match left"
    end
  end
end
