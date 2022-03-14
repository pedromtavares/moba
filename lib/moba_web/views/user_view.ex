defmodule MobaWeb.UserView do
  use MobaWeb, :view
  alias MobaWeb.ArenaView

  def opponent_for(duel, %{id: id}) when duel.user_id == id, do: duel.opponent
  def opponent_for(duel, _), do: duel.user

  def rewards_badge(rewards) when rewards == 0, do: ""

  def rewards_badge(rewards) when rewards > 0 do
    content_tag("span", "+#{rewards} Season Points", class: "badge badge-pill badge-light-success")
  end

  def rewards_badge(rewards) do
    content_tag("span", "#{rewards} Season Points", class: "badge badge-pill badge-light-dark")
  end
end
