defmodule MobaWeb.JungleLiveView do
  use MobaWeb, :live_view

  alias MobaWeb.{Tutorial, Shop}

  def mount(_, %{"user_id" => user_id}, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)
    hero = Game.current_pve_hero(socket.assigns.current_user)

    cond do
      hero && hero.finished_pve ->
        Game.update_pve_ranking!()
        {:ok, socket |> redirect(to: Routes.live_path(socket, MobaWeb.HeroLiveView, hero.id))}
      hero ->
        if connected?(socket), do: Tutorial.subscribe(hero.id)

        {:ok,
         assign(socket,
           current_hero: hero,
           targets: Game.list_targets(hero),
           tutorial_step: hero.user.tutorial_step,
           pending_battle: Engine.pending_battle(hero.id)
         )}
      true -> {:ok, socket |> redirect(to: "/game/pve")}
    end
  end

  def handle_params(_params, _uri, %{assigns: %{current_hero: hero}} = socket) do
    socket = if hero.gold >= 400 && length(hero.items) > 0, do: Tutorial.next_step(socket, 6), else: socket

    {:noreply, socket}
  end

  def handle_event("battle", %{"id" => id}, socket) do
    battle = Game.get_target!(id) |> Engine.create_pve_battle!()

    {:noreply,
     socket
     |> Tutorial.next_step(2)
     |> Tutorial.next_step(12)
     |> push_redirect(to: Routes.live_path(socket, MobaWeb.BattleLiveView, battle.id))}
  end

  def handle_event("tutorial3", _, socket) do
    {:noreply, socket |> Tutorial.next_step(3) |> Shop.open()}
  end

  def handle_event("tutorial5", _, socket) do
    {:noreply, socket |> Tutorial.next_step(5)}
  end

  def handle_event("tutorial12", _, socket) do
    {:noreply, socket |> Tutorial.next_step(12)}
  end

  def handle_info({"tutorial-step", %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def render(assigns) do
    MobaWeb.JungleView.render("index.html", assigns)
  end
end
