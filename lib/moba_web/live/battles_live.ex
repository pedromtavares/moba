defmodule MobaWeb.BattlesLive do
  use MobaWeb, :live_view

  alias MobaWeb.{BattleView, BattleLive}

  def mount(_, _session, socket) do
    with socket = socket_init(socket) do
      {:ok, socket}
    end
  end

  def handle_event("redirect", %{"id" => id}, socket) do
    {:noreply, socket |> push_redirect(to: Routes.live_path(socket, BattleLive, id))}
  end

  def render(assigns) do
    BattleView.render("index.html", assigns)
  end

  defp socket_init(%{assigns: %{current_hero: hero}} = socket) do
    with league_battles = Engine.list_battles(hero, "league"),
         pve_battles = Engine.list_battles(hero, "pve") do
      assign(socket,
        league_battles: league_battles,
        pve_battles: pve_battles,
        sidebar_code: "training"
      )
    end
  end
end
