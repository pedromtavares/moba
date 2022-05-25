defmodule MobaWeb.Admin.UserView do
  use MobaWeb, :view

  import Torch.TableView
  import Torch.FilterView

  def hero_for(user) do
    Moba.current_pve_hero(user)
  end
end
