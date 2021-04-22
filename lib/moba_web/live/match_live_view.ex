defmodule MobaWeb.MatchLiveView do
  use MobaWeb, :live_view

  def mount(_, session, socket) do
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)

    {:ok, assign(socket, current_hero: hero)}
  end

  def handle_params(_params, _uri, %{assigns: %{current_user: current_user}} = socket) do
    match = Game.last_match()
    last_pvp_hero = Game.last_pvp_hero(current_user.id)
    winners = Game.podium_for(match)
    winner_index = winners && Enum.find_index(winners, fn winner -> winner.user_id == current_user.id end)

    {:noreply,
     assign(socket,
       match: match,
       hero: last_pvp_hero,
       winners: winners,
       winner_index: winner_index
     )}
  end

  def render(assigns) do
    MobaWeb.MatchView.render("show.html", assigns)
  end
end
