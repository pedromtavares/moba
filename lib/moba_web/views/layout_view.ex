defmodule MobaWeb.LayoutView do
  use MobaWeb, :view

  alias Moba.Admin

  def guest?(%{user_id: user_id}), do: is_nil(user_id)

  def non_guest?(assigns), do: assigns[:current_player] && assigns[:current_player].user_id

  def show_notifications?(assigns) do
    assigns[:notifications] && assigns[:notifications] > 0
  end

  def show_sidebar?(assigns) do
    assigns[:current_player] && is_nil(assigns[:hide_sidebar]) && length(assigns[:current_player].hero_collection) > 0
  end

  def sidebar_class(codes, assigns) when is_list(codes) do
    if Enum.member?(codes, assigns[:sidebar_code]), do: "active", else: ""
  end

  def sidebar_class(code, assigns) do
    if assigns[:sidebar_code] == code, do: "active", else: ""
  end

  def show_footer?(assigns) do
    is_nil(assigns[:hide_footer]) && assigns[:current_player] && assigns[:current_player].user_id
  end

  def footer_stats do
    server_data = Admin.get_server_data()
    masters = (server_data && server_data.masters_count) || 0
    grandmasters = (server_data && server_data.grandmasters_count) || 0
    undefeated = (server_data && server_data.undefeated_count) || 0

    %{
      players: format_number(Admin.players_count()),
      heroes: format_number(Admin.heroes_count()),
      matches: format_number(Admin.matches_count()),
      masters: format_number(masters),
      grandmasters: format_number(grandmasters),
      undefeated: format_number(undefeated)
    }
  end

  defp format_number(n) do
    "#{n}"
    |> to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse(&1))
    |> Enum.reverse()
    |> Enum.join(",")
  end
end
