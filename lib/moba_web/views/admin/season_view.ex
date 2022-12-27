defmodule MobaWeb.Admin.SeasonView do
  use MobaWeb, :view

  import Torch.TableView
  import Torch.FilterView

  alias MobaWeb.PlayerView

  def xp_farm_percentage(%{total_xp_farm: xp_farm, total_gold_farm: gold_farm}) do
    total = xp_farm + gold_farm
    if total > 0, do: div(xp_farm * 100, total), else: 100
  end

  def gold_farm_percentage(hero), do: 100 - xp_farm_percentage(hero)

  def bottom_performing(stats, key) do
    data = stats[key]
    average = stats[:winrate]

    Enum.map(data, fn {record, winrate} ->
      {record, {winrate, winrate - average}}
    end)
    |> Enum.sort_by(fn {record, {winrate, diff}} -> diff end)
    |> Enum.take(10)
  end

  def top_performing(stats, key) do
    data = stats[key]
    average = stats[:winrate]

    Enum.map(data, fn {record, winrate} ->
      {record, {winrate, winrate - average}}
    end)
    |> Enum.sort_by(fn {record, {winrate, diff}} -> diff * -1 end)
    |> Enum.take(10)
  end
end
