defmodule MobaWeb.HeroLiveView do
  use MobaWeb, :live_view

  def mount(_, %{"user_id" => user_id}, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)

    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    hero = Game.get_hero!(id)
    ranking = Game.pve_search(hero)

    {:noreply, assign(socket, hero: hero, ranking: ranking, hide_join_new_match_button: true)}
  end

  def render(assigns) do
    MobaWeb.HeroView.render("show.html", assigns)
  end
end
