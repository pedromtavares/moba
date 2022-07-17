defmodule MobaWeb.LayoutView do
  use MobaWeb, :view

  def guest?(%{user_id: user_id}), do: is_nil(user_id)

  def non_guest?(assigns), do: assigns[:current_player] && assigns[:current_player].user_id

  def show_sidebar?(assigns) do
    assigns[:current_player] && is_nil(assigns[:hide_sidebar]) && length(assigns[:current_player].hero_collection) > 0
  end

  def sidebar_class(code, assigns) do
    if assigns[:sidebar_code] == code, do: "active", else: ""
  end
end
