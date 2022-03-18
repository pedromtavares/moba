defmodule MobaWeb.LayoutView do
  use MobaWeb, :view

  def sidebar_class(code, assigns) do
    if assigns[:sidebar_code] == code, do: "active", else: ""
  end
end
