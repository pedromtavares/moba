defmodule MobaWeb.Sidebar do
  use MobaWeb, :live_component

  def render(assigns) do
    MobaWeb.LayoutView.render("sidebar.html", assigns)
  end
end
