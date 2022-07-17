defmodule MobaWeb.DashboardLive do
  use MobaWeb, :live_view

  alias MobaWeb.TutorialComponent

  @base_hero_count Moba.base_hero_count()

  def mount(_, _session, socket) do
    with %{assigns: %{current_player: player}} = socket = socket_init(socket) do
      if connected?(socket), do: TutorialComponent.subscribe(player.id)

      {:ok, socket}
    end
  end

  def handle_event("show-finished", _, %{assigns: %{all_heroes: all_heroes, loaded: loaded}} = socket) do
    with visible = Enum.filter(all_heroes, & &1.finished_at),
         loaded = if(length(visible) < @base_hero_count, do: loaded ++ ["finished"], else: loaded) do
      {:noreply, assign(socket, loaded: loaded, visible_heroes: visible, filter: "finished")}
    end
  end

  def handle_event("show-unfinished", _, %{assigns: %{all_heroes: all_heroes, loaded: loaded}} = socket) do
    with visible = Enum.filter(all_heroes, &is_nil(&1.finished_at)),
         loaded = if(length(visible) < @base_hero_count, do: loaded ++ ["unfinished"], else: loaded) do
      {:noreply, assign(socket, loaded: loaded, visible_heroes: visible, filter: "unfinished")}
    end
  end

  def handle_event(
        "load-all",
        _,
        %{assigns: %{filter: filter, current_player: player, all_heroes: all_heroes, loaded: loaded}} = socket
      ) do
    with visible =
           if(filter == "finished",
             do: Game.list_all_finished_heroes(player.id),
             else: Game.list_all_unfinished_heroes(player.id)
           ),
         all_heroes = Enum.uniq(all_heroes ++ visible) do
      {:noreply, assign(socket, visible_heroes: visible, all_heroes: all_heroes, loaded: loaded ++ [filter])}
    end
  end

  def handle_event("archive", %{"id" => id}, %{assigns: %{current_player: player, current_hero: current_hero}} = socket) do
    hero = Game.get_hero!(id)

    if hero.player_id == player.id do
      Game.archive_hero!(hero)
      if hero.finished_at, do: Game.update_hero_collection!(hero)

      current_hero = if current_hero && hero.id == current_hero.id, do: nil, else: current_hero

      {:noreply,
       assign(socket,
         current_hero: current_hero,
         visible_heroes: Enum.reject(socket.assigns.visible_heroes, &(&1.id == hero.id))
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("continue", %{"id" => id}, %{assigns: %{current_player: player}} = socket) do
    hero = Game.get_hero!(id)

    if hero.player_id == player.id do
      player = Game.set_current_pve_hero!(player, id)

      {:noreply,
       socket
       |> assign(current_hero: hero, current_player: player)
       |> push_redirect(to: Routes.live_path(socket, MobaWeb.TrainingLive))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("tutorial1", _, socket) do
    {:noreply, socket |> TutorialComponent.next_step(21)}
  end

  def handle_event("finish-tutorial", _, socket) do
    {:noreply, TutorialComponent.finish_base(socket)}
  end

  def handle_info({:tutorial, %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def render(assigns) do
    MobaWeb.DashboardView.render("index.html", assigns)
  end

  defp check_tutorial(%{assigns: %{current_player: player}} = socket) do
    %{assigns: %{tutorial_step: step}} = socket = TutorialComponent.next_step(socket, 20)

    if step == 29 && player.pve_tier > 0 do
      socket
      |> TutorialComponent.next_step(30)
      |> push_redirect(to: Routes.live_path(socket, MobaWeb.ArenaLive))
    else
      socket
    end
  end

  defp heroes_assigns(%{assigns: %{current_player: player}} = socket) do
    with unfinished_heroes = Game.latest_unfinished_heroes(player.id),
         finished_heroes = Game.latest_finished_heroes(player.id),
         all_heroes = unfinished_heroes ++ finished_heroes,
         filter = if(Enum.any?(unfinished_heroes), do: "unfinished", else: "finished"),
         visible_heroes = if(filter == "unfinished", do: unfinished_heroes, else: finished_heroes),
         collection_codes = Enum.map(player.hero_collection, & &1["code"]),
         blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes)),
         loaded = if(length(visible_heroes) < @base_hero_count, do: [filter], else: []) do
      assign(socket,
        all_heroes: all_heroes,
        blank_collection: blank_collection,
        collection_codes: collection_codes,
        filter: filter,
        loaded: loaded,
        unfinished_heroes: unfinished_heroes,
        visible_heroes: visible_heroes
      )
    end
  end

  defp socket_init(%{assigns: %{current_player: player}} = socket) do
    socket
    |> assign(sidebar_code: "base", tutorial_step: player.tutorial_step)
    |> heroes_assigns()
    |> check_tutorial()
  end
end
