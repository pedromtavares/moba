defmodule MobaWeb.V2.DashboardLive do
  use MobaWeb, :v2_live_view

  def mount(_params, _session, socket) do
    %{assigns: %{current_player: player}} = socket

    {:ok, load_heroes(socket, player)}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    %{assigns: %{all_heroes: all_heroes}} = socket

    visible =
      case filter do
        "finished" -> Enum.filter(all_heroes, & &1.finished_at)
        "unfinished" -> Enum.filter(all_heroes, &is_nil(&1.finished_at))
        _ -> all_heroes
      end

    {:noreply, assign(socket, visible_heroes: visible, filter: filter)}
  end

  def handle_event("continue", %{"id" => id}, socket) do
    %{assigns: %{current_player: player}} = socket
    hero = Game.get_hero!(id)

    if hero.player_id == player.id do
      player = Game.set_current_pve_hero!(player, id)

      {:noreply,
       socket
       |> assign(current_hero: hero, current_player: player)
       |> push_navigate(to: ~p"/v2/base")}
    else
      {:noreply, socket}
    end
  end

  # Private functions

  defp load_heroes(socket, player) do
    unfinished = Game.latest_unfinished_heroes(player.id)
    finished = Game.latest_finished_heroes(player.id)
    all_heroes = unfinished ++ finished

    filter = if Enum.any?(unfinished), do: "unfinished", else: "finished"

    visible =
      if filter == "unfinished", do: unfinished, else: finished

    assign(socket,
      all_heroes: all_heroes,
      visible_heroes: visible,
      filter: filter
    )
  end
end
