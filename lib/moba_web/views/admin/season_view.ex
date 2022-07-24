defmodule MobaWeb.Admin.SeasonView do
  use MobaWeb, :view

  import Torch.TableView
  import Torch.FilterView

  def xp_farm_percentage(%{total_xp_farm: xp_farm, total_gold_farm: gold_farm}) do
    total = xp_farm + gold_farm
    if total > 0, do: div(xp_farm * 100, total), else: 100
  end

  def gold_farm_percentage(hero), do: 100 - xp_farm_percentage(hero)

  defdelegate username(player), to: MobaWeb.UserView
end
