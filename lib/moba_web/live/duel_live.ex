defmodule MobaWeb.DuelLive do
  use MobaWeb, :live_view

  alias MobaWeb.DuelView

  def mount(%{"id" => duel_id}, _, socket) do
    with %{assigns: %{channel: channel}} = socket = socket_init(duel_id, socket) do
      if connected?(socket) do
        MobaWeb.subscribe(channel)
        check_phase()
      end

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
          tier: player.pve_tier,
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
      Game.continue_duel!(duel, hero)
      heroes = heroes -- [hero]

      {:noreply, assign(socket, heroes: heroes)}
    end
  end

  def handle_event("rematch", _, %{assigns: %{duel: duel, current_player: player}} = socket) do
    with other = if(player.id == duel.player_id, do: duel.opponent_player, else: duel.player),
         can_challenge? = player.status == "available" && other.status == "available" do
      if can_challenge?, do: Game.duel_challenge(player, other)

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

  def handle_info(:check_phase, %{assigns: %{duel: %{phase: phase} = duel}} = socket)
      when phase not in ["user_battle", "opponent_battle", "finished"] do
    Process.send_after(self(), :check_phase, 1000 + Enum.random(1..200))

    if DuelView.pick_timer(duel, Timex.now()) <= 0 do
      Game.continue_duel!(duel, :auto)
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

  defp socket_init(duel_id, socket) do
    with channel = "duel-#{duel_id}",
         changeset = Accounts.change_message(),
         current_time = Timex.now(),
         duel = Game.get_duel!(duel_id),
         player = socket.assigns.current_player,
         heroes = Game.available_pvp_heroes(player, [duel.player_first_pick_id, duel.opponent_first_pick_id]),
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
