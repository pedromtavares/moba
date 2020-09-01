defmodule MobaWeb.HeroLiveView do
  use Phoenix.LiveView

  alias MobaWeb.{Tutorial, Shop}
  alias Moba.{Game, Engine}

  alias MobaWeb.Router.Helpers, as: Routes

  def mount(_, %{"hero_id" => hero_id} = session, socket) do
    if connected?(socket) do
      hero_id
      |> Game.subscribe_to_hero()
      |> Tutorial.subscribe()
      |> Shop.subscribe()
    end

    socket = assign_new(socket, :current_hero, fn -> Game.get_hero!(hero_id) end)
    hero = socket.assigns.current_hero
    step = session["tutorial_step"] || hero.user.tutorial_step

    {:ok,
     assign(socket,
       editing: false,
       show_build: false,
       unreads: Engine.unread_battles_count(hero),
       show_shop: Enum.member?([3, 7, 8, 9], step),
       tutorial_step: step,
       origin: session["origin"],
       current_mode: session["current_mode"]
     )}
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
    hero = Game.level_up_skill!(current, code)

    Game.broadcast_to_hero(hero.id)

    {:noreply, assign(socket, current_hero: hero)}
  end

  def handle_event("league", _, %{assigns: %{current_hero: hero}} = socket) do
    socket = Tutorial.next_step(socket, 10)

    battle =
      hero
      |> Game.redeem_league!()
      |> Engine.create_league_battle!()

    {:noreply, socket |> push_redirect(to: Routes.live_path(socket, MobaWeb.BattleLiveView, battle.id))}
  end

  def handle_event("start-edit", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("finalize-edit", params, %{assigns: %{current_hero: current}} = socket) do
    build =
      Game.update_build!(current.active_build, %{
        skill_order: params_to_order(params["skill_order"]),
        item_order: params_to_order(params["item_order"])
      })

    {:noreply, assign(socket, editing: false, current_hero: %{current | active_build: build})}
  end

  def handle_event("switch-build", _, %{assigns: assigns} = socket) do
    {:noreply, assign(socket, current_hero: Game.switch_build!(assigns.current_hero))}
  end

  def handle_event("show-build", _, socket) do
    {:noreply, assign(socket, show_build: true)}
  end

  def handle_event("show-navigation", _, socket) do
    {:noreply, assign(socket, show_build: false)}
  end

  def handle_event("close-shop", _, socket) do
    {:noreply, assign(socket, show_shop: false) |> Tutorial.next_step(10)}
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

  def handle_info({"unread", %{hero_id: hero_id}}, socket) do
    unreads =
      hero_id
      |> Game.get_hero!()
      |> Engine.unread_battles_count()

    {:noreply, assign(socket, unreads: unreads)}
  end

  def handle_info({"tutorial-step", %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def render(assigns) do
    MobaWeb.HeroView.render("index.html", assigns)
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
end
