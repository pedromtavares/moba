defmodule MobaWeb.LayoutView do
  use MobaWeb, :view

  def non_guest?(assigns), do: assigns[:current_user] && not assigns[:current_user].is_guest

  def show_sidebar?(assigns) do
    non_guest?(assigns) && is_nil(assigns[:hide_sidebar]) && length(assigns[:current_user].hero_collection) > 0
  end

  def sidebar_class(code, assigns) do
    if assigns[:sidebar_code] == code, do: "active", else: ""
  end
end
