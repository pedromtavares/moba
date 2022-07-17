defmodule MobaWeb.CurrentHeroLive do
  use MobaWeb, :live_view

  alias MobaWeb.{TutorialComponent, Shop}

  def mount(_, session, socket) do
    with %{assigns: %{current_hero: hero}} = socket = socket_init(session, socket) do
      if connected?(socket) do
        TutorialComponent.subscribe(hero.player_id)

        hero.id
        |> Game.subscribe_to_hero()
        |> Shop.subscribe()
      end

      {:ok, socket}
    end
  end

  # cheat mechanism for easy levels, unavailable to live players
  def handle_event("level", _, %{assigns: %{current_hero: current}} = socket) do
    hero =
      if Application.get_env(:moba, :env) == :dev do
        Game.level_cheat(current)
      else
        current
      end

    Game.broadcast_to_hero(current.id)
    {:noreply, assign(socket, current_hero: hero)}
  end

  def handle_event("skill", %{"code" => code}, %{assigns: %{current_hero: current}} = socket) do
    with hero = Game.level_up_skill!(current, code) do
      Game.broadcast_to_hero(hero.id)
      {:noreply, assign(socket, current_hero: hero)}
    end
  end

  def handle_event("start-edit", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("finalize-edit", params, %{assigns: %{current_hero: current}} = socket) do
    hero =
      Game.update_hero!(current, %{
        skill_order: params_to_order(params["skill_order"]),
        item_order: params_to_order(params["item_order"])
      })

    {:noreply, assign(socket, editing: false, current_hero: hero)}
  end

  def handle_event("show-build", _, socket) do
    {:noreply, assign(socket, show_build: true)}
  end

  def handle_event("show-navigation", _, socket) do
    {:noreply, assign(socket, show_build: false)}
  end

  def handle_event("close-shop", _, socket) do
    {:noreply, assign(socket, show_shop: false) |> TutorialComponent.next_step(10)}
  end

  def handle_event("toggle-shop", _, socket) do
    {:noreply, assign(socket, show_shop: !socket.assigns.show_shop)}
  end

  def handle_info({"toggle-shop", _}, socket) do
    {:noreply, assign(socket, show_shop: !socket.assigns.show_shop)}
  end

  def handle_info({"open-shop", _}, socket) do
    {:noreply, assign(socket, show_shop: true)}
  end

  def handle_info({"close-shop", _}, socket) do
    {:noreply, assign(socket, show_shop: false)}
  end

  def handle_info({"hero", %{id: id}}, socket) do
    {:noreply, assign(socket, current_hero: Game.get_hero!(id))}
  end

  def handle_info({:tutorial, %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def render(assigns) do
    MobaWeb.CurrentHeroView.render("show.html", assigns)
  end

  defp params_to_order(nil), do: []

  defp params_to_order(params) do
    Enum.sort(params, fn {_, v1}, {_, v2} ->
      String.to_integer(v1) <= String.to_integer(v2)
    end)
    |> Enum.map(fn {code, _} ->
      code
    end)
  end

  defp socket_init(%{"hero" => hero} = session, socket) do
    with step = session["tutorial_step"] || hero.player.tutorial_step,
         show_shop = Enum.member?([3, 7, 8, 9], step) do
      assign(socket,
        current_hero: hero,
        current_player: hero.player,
        editing: false,
        show_build: false,
        show_shop: show_shop,
        tutorial_step: step
      )
    end
  end
end
