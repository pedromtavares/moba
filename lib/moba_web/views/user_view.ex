defmodule MobaWeb.UserView do
  use MobaWeb, :view
  alias MobaWeb.{ArenaView, DashboardView}

  defdelegate avatar_class(hero), to: DashboardView

  def in_ranking?(ranking, %{id: id}) do
    ranking
    |> Enum.map(& &1.id)
    |> Enum.member?(id)
  end

  def opponent_for(duel, %{id: id}) when duel.player_id == id, do: duel.opponent_player
  def opponent_for(duel, _), do: duel.player

  def registered_label(player) do
    time = if player.user, do: player.user.inserted_at, else: player.inserted_at
    formatted = time |> Timex.format("{relative}", :relative) |> elem(1)

    cond do
      player.bot_options -> "A.I. Player"
      player.user -> "Registered #{formatted}"
      true -> "Joined #{formatted}"
    end
  end

  def rewards_badge(rewards) when rewards == 0, do: ""

  def rewards_badge(rewards) when rewards > 0 do
    content_tag("span", "+#{rewards} Season Points", class: "badge badge-pill badge-light-success")
  end

  def rewards_badge(rewards) do
    content_tag("span", "#{rewards} Season Points", class: "badge badge-pill badge-light-dark")
  end

  def username(%{bot_options: %{name: name}}), do: name
  def username(%{user: %{username: username}}), do: username
  def username(_), do: "Guest"
end
