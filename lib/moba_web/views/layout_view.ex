defmodule MobaWeb.LayoutView do
  use MobaWeb, :view

  def wrapper_for(conn) do
    case List.first(conn.path_info) do
      "jungle" -> "wrapper-jungle"
      "arena" -> "wrapper-arena"
      "battles" -> "wrapper-battles"
      _ -> ""
    end
  end
end
