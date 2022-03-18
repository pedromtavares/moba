defmodule MobaWeb.BattlesLiveView do
  use MobaWeb, :live_view

  alias MobaWeb.{BattleView, BattleLiveView}

  def mount(_, %{"hero_id" => hero_id}, socket) do
    socket = assign_new(socket, :current_hero, fn -> Game.get_hero!(hero_id) end)

    {:ok, assign(socket, battles: %{pve: [], league: []}), temporary_assigns: [extra_battles: []]}
  end

  def handle_params(_params, _uri, %{assigns: %{current_hero: hero}} = socket) do
    pve_list = Engine.list_battles(hero, "pve")
    league_list = Engine.list_battles(hero, "league")

    {:noreply,
     assign(socket,
       battles: %{
         pve: pve_list,
         league: league_list
       },
       pages: %{
         pve: initial_page_for(pve_list),
         league: initial_page_for(league_list)
       },
       sidebar_code: "training"
     )}
  end

  def handle_event(
        "page",
        %{"number" => number, "type" => type},
        %{assigns: %{current_hero: hero, pages: pages}} = socket
      ) do
    page = process_page(number)
    key = String.to_atom(type)
    list = Engine.list_battles(hero, type, page)

    pages =
      if Enum.count(list) >= 5 do
        Map.put(pages, key, page)
      else
        Map.put(pages, key, 0)
      end

    battles = %{pve: [], league: []}

    {:noreply, assign(socket, pages: pages, battles: Map.put(battles, key, list))}
  end

  def handle_event("redirect", %{"id" => id}, socket) do
    {:noreply, socket |> push_redirect(to: Routes.live_path(socket, BattleLiveView, id))}
  end

  def render(assigns) do
    BattleView.render("index.html", assigns)
  end

  defp process_page(page) do
    result = String.to_integer(page)

    if result <= 0 do
      1
    else
      result
    end
  end

  defp initial_page_for(list) do
    (list && length(list) == 5 && 1) || 0
  end
end
