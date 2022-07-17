defmodule MobaWeb.DuelLive do
  use MobaWeb, :live_view

  alias MobaWeb.DuelView

  def mount(%{"id" => duel_id}, %{"player_id" => player_id}, socket) do
    with %{assigns: %{channel: channel, duel: duel}} = socket = socket_init(duel_id, player_id, socket) do
      if connected?(socket), do: MobaWeb.subscribe(channel)
      if duel.type == "pvp", do: check_phase()

      {:ok, socket}
    end
  end

  def handle_event(
        "create-message",
        params,
        %{assigns: %{current_player: %{user: user} = player, channel: channel}} = socket
      ) do
    with body = params["message"]["body"],
         length = String.length(body),
         proper_size? = length > 1 && length <= 200 do
      if proper_size? do
        Accounts.create_message!(%{
          body: body,
          author: user.username,
          tier: player.pvp_tier,
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
  end

  def handle_event("pick", %{"id" => hero_id}, %{assigns: %{duel: duel, heroes: heroes}} = socket) do
    with hero = Enum.find(heroes, &(&1.id == String.to_integer(hero_id))) do
      Game.next_duel_phase!(duel, hero)

      {:noreply, socket}
    end
  end

  def handle_event("rematch", _, %{assigns: %{duel: duel, current_user: current_user}} = socket) do
    with other = if(current_user.id == duel.user_id, do: duel.opponent, else: duel.user),
         can_challenge? = current_user.status == "available" && other.status == "available" do
      if can_challenge?, do: Game.duel_challenge(current_user, other)

      {:noreply, socket}
    end
  end

  def handle_event("delete-message", %{"id" => id}, socket) do
    with message = Accounts.get_message!(id),
         _ <- Accounts.delete_message(message),
         messages = List.delete(socket.assigns.messages, message) do
      {:noreply, assign(socket, messages: messages)}
    end
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

  defp socket_init(duel_id, player_id, socket) do
    with channel = "duel-#{duel_id}",
         changeset = Accounts.change_message(),
         current_time = Timex.now(),
         duel = Game.get_duel!(duel_id),
         heroes = Game.list_pickable_heroes(player_id, duel.inserted_at),
         first_battle = Engine.first_duel_battle(duel),
         last_battle = Engine.last_duel_battle(duel),
         messages = Accounts.latest_messages(channel, "general", 20) |> Enum.reverse() do
      assign(socket,
        changeset: changeset,
        channel: channel,
        current_time: current_time,
        duel: duel,
        first_battle: first_battle,
        heroes: heroes,
        last_battle: last_battle,
        messages: messages
      )
    end
  end
end
