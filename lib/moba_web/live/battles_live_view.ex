defmodule MobaWeb.BattlesLiveView do
  use Phoenix.LiveView

  alias Moba.{Engine, Game}
  alias MobaWeb.{BattleView, BattleLiveView, BattlesLiveView}
  alias MobaWeb.Router.Helpers, as: Routes

  def mount(_, %{"hero_id" => hero_id} = session, socket) do
    socket = assign_new(socket, :current_hero, fn -> Game.get_hero!(hero_id) end)
    hero = socket.assigns.current_hero

    {:ok,
     assign(socket,
       battles: %{pvp: [], pve: [], league: [], pvp_defended: []},
       unread_list: [],
       unreads: Engine.unread_battles_count(hero),
       current_mode: session["current_mode"] || "pve"
     ), temporary_assigns: [extra_battles: []]}
  end

  def handle_params(_params, _uri, %{assigns: %{current_hero: hero, current_mode: mode}} = socket) do
    pve_list = mode == "pve" && Engine.list_battles(hero, "pve")
    league_list = mode == "pve" && Engine.list_battles(hero, "league")
    pvp_list = mode == "pvp" && Engine.list_battles(hero, "pvp")
    pvp_defended_list = mode == "pvp" && Engine.list_battles(hero, "pvp_defended")

    {:noreply,
     assign(socket,
       battles: %{
         pvp: pvp_list,
         pvp_defended: pvp_defended_list,
         pve: pve_list,
         league: league_list
       },
       pages: %{
         pve: initial_page_for(pve_list),
         league: initial_page_for(league_list),
         pvp: initial_page_for(pvp_list),
         pvp_defended: initial_page_for(pvp_defended_list)
       }
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

    battles = %{pvp: [], pve: [], league: []}

    {:noreply, assign(socket, pages: pages, battles: Map.put(battles, key, list))}
  end

  def handle_event("redirect", %{"id" => id}, socket) do
    {:noreply, socket |> push_redirect(to: Routes.live_path(socket, BattleLiveView, id))}
  end

  def handle_event("read-all", _, socket) do
    Engine.read_all_battles_for(socket.assigns.current_hero)
    {:noreply, socket |> assign(unreads: 0) |> push_patch(to: Routes.live_path(socket, BattlesLiveView))}
  end

  def render(%{current_mode: "pve"} = assigns) do
    BattleView.render("index_pve.html", assigns)
  end

  def render(assigns) do
    BattleView.render("index_pvp.html", assigns)
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
