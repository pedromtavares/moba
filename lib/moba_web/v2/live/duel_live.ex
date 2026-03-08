defmodule MobaWeb.V2.DuelLive do
  use MobaWeb, :v2_live_view

  embed_templates "duel_live/*"

  def mount(%{"id" => duel_id}, _session, socket) do
    socket = socket_init(duel_id, socket)

    if connected?(socket) do
      MobaWeb.subscribe(socket.assigns.channel)
      schedule_phase_check()
    end

    {:ok, socket}
  end

  def handle_event(
        "create-message",
        %{"message" => %{"body" => body}},
        %{assigns: %{current_player: %{user: user} = player, channel: channel}} = socket
      ) do
    length = String.length(body)

    if length > 1 and length <= 200 do
      Accounts.create_message!(%{
        body: body,
        author: user.username,
        tier: player.pve_tier,
        channel: channel,
        topic: "general",
        is_admin: user.is_admin,
        user_id: user.id
      })

      {:noreply, reset_message_form(socket, %{user_id: Timex.now()})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("pick", %{"id" => hero_id}, %{assigns: %{duel: duel, heroes: heroes}} = socket) do
    hero_id = parse_int(hero_id)
    hero = Enum.find(heroes, &(&1.id == hero_id))

    if hero do
      Game.continue_duel!(duel, hero)
      {:noreply, assign(socket, heroes: heroes -- [hero])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("rematch", _, %{assigns: %{duel: duel, current_player: player}} = socket) do
    other = if player.id == duel.player_id, do: duel.opponent_player, else: duel.player

    if player.status == "available" && other.status == "available" do
      Game.duel_challenge(player, other)
    end

    {:noreply, socket}
  end

  def handle_event("delete-message", %{"id" => id}, %{assigns: %{messages: messages}} = socket) do
    message = Accounts.get_message!(id)
    {:ok, _} = Accounts.delete_message(message)
    {:noreply, assign(socket, messages: List.delete(messages, message))}
  end

  def handle_info({"phase", _}, socket) do
    {:noreply, refresh_duel(socket)}
  end

  def handle_info({"general", message}, %{assigns: %{messages: messages}} = socket) do
    {:noreply, assign(socket, messages: messages ++ [message])}
  end

  def handle_info(:check_phase, %{assigns: %{duel: %{phase: phase} = duel}} = socket)
      when phase not in ["player_battle", "opponent_battle", "finished"] do
    schedule_phase_check()

    duel =
      if pick_timer(duel, Timex.now()) <= 0 do
        Game.continue_duel!(duel, :auto)
      else
        duel
      end

    {:noreply, socket |> assign(current_time: Timex.now(), duel: duel) |> refresh_duel()}
  end

  def handle_info(:check_phase, socket) do
    {:noreply, assign(socket, current_time: Timex.now())}
  end

  def render(assigns), do: show(assigns)

  defp socket_init(duel_id, %{assigns: %{current_player: player}} = socket) do
    duel = Game.get_duel!(duel_id)
    channel = "duel-#{duel_id}"
    heroes = Game.available_pvp_heroes(player, [duel.player_first_pick_id, duel.opponent_first_pick_id])

    assign(socket,
      sidebar_code: "arena",
      channel: channel,
      current_time: Timex.now(),
      duel: duel,
      heroes: heroes,
      first_battle: Engine.first_duel_battle(duel),
      last_battle: Engine.last_duel_battle(duel),
      messages: Accounts.latest_messages(channel, "general", 20) |> Enum.reverse()
    )
    |> reset_message_form()
  end

  defp refresh_duel(%{assigns: %{duel: duel}} = socket) do
    duel = Game.get_duel!(duel.id)

    assign(socket,
      duel: duel,
      first_battle: Engine.first_duel_battle(duel),
      last_battle: Engine.last_duel_battle(duel)
    )
  end

  defp schedule_phase_check, do: Process.send_after(self(), :check_phase, 500)

  defp pick_timer(%{phase_changed_at: changed}, current_time) do
    changed
    |> Timex.shift(seconds: Moba.duel_timer_in_seconds())
    |> Timex.diff(current_time, :seconds)
  end

  defp duel_finished?(%{phase: "finished"}), do: true
  defp duel_finished?(_), do: false

  defp casual?(%{player: %{pvp_points: player_sp}, opponent_player: %{pvp_points: opponent_sp}})
       when player_sp - opponent_sp < -200 or player_sp - opponent_sp > 200,
       do: true

  defp casual?(_), do: false

  defp show_timer?(%{phase: phase}) when phase not in ["player_battle", "opponent_battle", "finished"], do: true
  defp show_timer?(_), do: false

  defp user_instructions(%{phase: phase, player: player}) when phase in ["player_first_pick", "player_second_pick"] do
    "#{player.user.username}, it's your turn to pick"
  end

  defp user_instructions(_), do: ""

  defp opponent_instructions(%{phase: phase, opponent_player: opponent})
       when phase in ["opponent_first_pick", "opponent_second_pick"] do
    "#{opponent.user.username}, it's your turn to pick"
  end

  defp opponent_instructions(_), do: ""

  defp phase_class(%{phase: phase}, current_phase) when phase == current_phase, do: "nav-link no-action active"
  defp phase_class(_, _), do: "nav-link no-action"

  defp show_rematch?(%{duel: duel, current_player: player}) do
    duel_finished?(duel) &&
      both_online?(duel, player) &&
      (player.id == duel.player_id || player.id == duel.opponent_player_id)
  end

  defp battle_turn_hero(battle, hero_id) do
    turn = List.last(battle.turns)

    if turn.attacker.hero_id == hero_id do
      turn.attacker
    else
      turn.defender
    end
  end

  defp both_online?(%{player: %{id: player_id}, opponent_player: %{id: opponent_id}}, current_player) do
    online_ids =
      MobaWeb.Presence.list("online")
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)
      |> Enum.map(& &1.player_id)
      |> Kernel.++([current_player.id])

    Enum.member?(online_ids, player_id) && Enum.member?(online_ids, opponent_id)
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value), do: String.to_integer(value)

  defp reset_message_form(socket, attrs \\ %{}) do
    assign(socket,
      message_form: to_form(Accounts.change_message(attrs)),
      message_form_nonce: (socket.assigns[:message_form_nonce] || 0) + 1
    )
  end
end
