defmodule MobaWeb.DuelLiveView do
  use MobaWeb, :live_view

  alias MobaWeb.DuelView

  def mount(%{"id" => duel_id}, %{"user_id" => user_id}, socket) do
    socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)
    channel = "duel-#{duel_id}"

    if connected?(socket) do
      MobaWeb.subscribe(channel)
    end

    messages = Accounts.latest_messages(channel, "general", 20) |> Enum.reverse()
    changeset = Accounts.change_message()
    duel = Game.get_duel!(duel_id)

    if duel.type == "pvp", do: check_phase()

    {:ok,
     assign(socket,
       duel: duel,
       heroes: Game.eligible_heroes_for_pvp(user_id, duel.inserted_at),
       first_battle: Engine.first_duel_battle(duel),
       last_battle: Engine.last_duel_battle(duel),
       changeset: changeset,
       messages: messages,
       channel: channel,
       current_time: Timex.now()
     )}
  end

  def handle_event("create-message", params, %{assigns: %{current_user: user, channel: channel}} = socket) do
    body = params["message"]["body"]
    length = String.length(body)

    if length > 1 && length <= 200 do
      Accounts.create_message!(%{
        body: body,
        author: user.username,
        tier: user.season_tier,
        channel: channel,
        topic: "general",
        is_admin: user.is_admin,
        user_id: user.id
      })

      {:noreply, assign(socket, changeset: Accounts.change_message(%{user_id: Timex.now()}))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("pick", %{"id" => hero_id}, %{assigns: %{duel: duel, heroes: heroes}} = socket) do
    hero = Enum.find(heroes, &(&1.id == String.to_integer(hero_id)))
    Game.next_duel_phase!(duel, hero)

    {:noreply, socket}
  end

  def handle_event("rematch", _, %{assigns: %{duel: duel, current_user: current_user}} = socket) do
    other = if current_user.id == duel.user_id, do: duel.opponent, else: duel.user

    if current_user.status == "available" && other.status == "available" do
      Game.duel_challenge(current_user, other)
    end

    {:noreply, socket}
  end

  def handle_event("delete-message", %{"id" => id}, socket) do
    message = Accounts.get_message!(id)
    Accounts.delete_message(message)

    {:noreply, assign(socket, messages: socket.assigns.messages -- [message])}
  end

  def handle_info({"phase", _}, socket) do
    with duel = Game.get_duel!(socket.assigns.duel.id),
         first_battle = Engine.first_duel_battle(duel),
         last_battle = Engine.last_duel_battle(duel) do
      {:noreply, assign(socket, duel: duel, first_battle: first_battle, last_battle: last_battle)}
    end
  end

  def handle_info({"general", message}, %{assigns: %{messages: messages}} = socket) do
    {:noreply, assign(socket, messages: messages ++ [message])}
  end

  def handle_info(:check_phase, %{assigns: %{duel: %{type: "pvp", phase: phase} = duel}} = socket)
      when phase not in ["user_battle", "opponent_battle", "finished"] do
    Process.send_after(self(), :check_phase, 1000)

    if DuelView.pick_timer(duel, Timex.now()) <= 0 do
      Game.auto_next_duel_phase!(duel)
    end

    {:noreply, assign(socket, current_time: Timex.now())}
  end

  def handle_info(:check_phase, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    DuelView.render("show.html", assigns)
  end

  defp check_phase do
    Process.send_after(self(), :check_phase, 500)
  end
end
