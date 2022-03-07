defmodule MobaWeb.DuelLiveView do
  use MobaWeb, :live_view

  def mount(%{"id" => duel_id}, %{"user_id" => user_id}, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)

    if connected?(socket) do
      MobaWeb.subscribe("duel-#{duel_id}")
    end

    duel = Game.get_duel!(duel_id)

    {:ok,
     assign(socket,
       duel: duel,
       heroes: Game.eligible_heroes_for_pvp(user_id, duel.inserted_at),
       first_battle: Engine.first_duel_battle(duel),
       last_battle: Engine.last_duel_battle(duel)
     )}
  end

  def handle_info({"phase", _}, socket) do
    with duel = Game.get_duel!(socket.assigns.duel.id),
         first_battle = Engine.first_duel_battle(duel),
         last_battle = Engine.last_duel_battle(duel) do
      {:noreply, assign(socket, duel: duel, first_battle: first_battle, last_battle: last_battle)}
    end
  end

  def handle_event("pick", %{"id" => hero_id}, %{assigns: %{duel: duel, heroes: heroes}} = socket) do
    hero = Enum.find(heroes, &(&1.id == String.to_integer(hero_id)))
    Game.next_duel_phase!(duel, hero)

    {:noreply, socket}
  end

  def handle_event("rematch", _, %{assigns: %{duel: duel, current_user: current_user}} = socket) do
    other = if current_user.id == duel.user_id, do: duel.opponent, else: duel.user

    Game.duel_challenge(current_user, other)

    {:noreply, socket}
  end

  def render(assigns) do
    MobaWeb.DuelView.render("show.html", assigns)
  end
end
