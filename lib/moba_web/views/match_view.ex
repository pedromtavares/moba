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
end
