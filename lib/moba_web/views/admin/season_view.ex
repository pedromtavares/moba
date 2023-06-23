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
    mapped_stats(stats, key)
    |> Enum.sort_by(fn {_record, {_winrate, _, diff}} -> diff end)
    |> Enum.take(10)
  end

  def top_performing(stats, key) do
    mapped_stats(stats, key)
    |> Enum.sort_by(fn {_record, {_winrate, _, diff}} -> diff * -1 end)
    |> Enum.take(10)
  end

  def winrate_class(diff, "pvp") when diff > 4 or diff < -4, do: "text-danger"
  def winrate_class(diff, "plebs") when diff > 4 or diff < -4, do: "text-danger"
  def winrate_class(diff, "elite") when diff > 8 or diff < -8, do: "text-danger"
  def winrate_class(diff, _) when diff > 10 or diff < -10, do: "text-danger"
  def winrate_class(diff, "pvp") when diff > 2 or diff < -2, do: "text-warning"
  def winrate_class(diff, "plebs") when diff > 2 or diff < -2, do: "text-warning"
  def winrate_class(diff, "elite") when diff > 4 or diff < -4, do: "text-warning"
  def winrate_class(diff, _) when diff > 5 or diff < -5, do: "text-warning"
  def winrate_class(_, _), do: "text-success"

  defp mapped_stats(stats, key) do
    data = stats[key]
    average = stats[:winrate]

    Enum.map(data, fn {record, {winrate, total}} ->
      {record, {winrate, total, winrate - average}}
    end)
  end
end
