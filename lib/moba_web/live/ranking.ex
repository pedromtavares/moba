defmodule MobaWeb.Ranking do
  use MobaWeb, :live_component

  def mount(socket) do
    {:ok, assign(socket, page: 1), temporary_assigns: [ranking: []]}
  end

  def update(%{hero: hero}, socket) do
    {:ok,
     assign(socket,
       hero: hero,
       league_tier: hero.league_tier,
       ranking: Game.paged_pvp_ranking(hero.league_tier, 1)
     )}
  end

  def handle_event("battle", %{"id" => id, "number" => build_id}, socket) do
    send(self(), {"battle", %{id: id, build_id: build_id}})
    {:noreply, socket}
  end

  def handle_event("page", %{"number" => number}, socket) do
    page = process_page(number)
    results = Game.paged_pvp_ranking(socket.assigns.league_tier, page)
    {:noreply, assign(socket, page: page, ranking: results)}
  end

  def render(assigns) do
    MobaWeb.ArenaView.render("ranking.html", assigns)
  end

  defp process_page(page) do
    result = String.to_integer(page)

    if result <= 0 do
      1
    else
      result
    end
  end
end
