defmodule MobaWeb.Admin.UserView do
  use MobaWeb, :view

  import Torch.TableView
  import Torch.FilterView

  def hero_for(user) do
    Moba.Game.current_pve_hero(user)
  end
end
