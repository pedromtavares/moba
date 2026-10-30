defmodule MobaWeb.V2.DuelChallengeLive do
  use Phoenix.LiveView, layout: false

  alias Moba.Game
  alias MobaWeb.Presence
  alias MobaWeb.V2.Layouts
  import Moba.Utils, only: [username: 1]

  embed_templates "duel_challenge_live/*"

  def mount(_, %{"player_id" => player_id}, socket) do
    player = Game.get_player!(player_id)

    if connected?(socket) do
      MobaWeb.subscribe("player-#{player.id}")
      Presence.track_player(self(), player)
    end

    {:ok, assign(socket, current_player: player, challenge: nil, state: nil, seconds: 30)}
  end

  def render(assigns), do: overlay(assigns)

  def handle_info({"challenge", %{player_id: challenger_id, opponent_id: opponent_id}}, socket) do
    player = socket.assigns.current_player
    outgoing = player.id == challenger_id
    other = Game.get_player!(if outgoing, do: opponent_id, else: challenger_id)
    expires_at = DateTime.add(DateTime.utc_now(), 30)
    token = make_ref()
    Process.send_after(self(), {:challenge_tick, token}, 1000)
    player = Game.update_player!(player, %{last_challenge_at: Timex.now()})

    challenge = %{other: other, outgoing: outgoing, expires_at: expires_at, token: token}
    {:noreply, assign(socket, current_player: player, challenge: challenge, state: "pending", seconds: 30)}
  end

  def handle_info(
        {:challenge_tick, token},
        %{assigns: %{challenge: %{token: token} = challenge, state: "pending"}} = socket
      ) do
    seconds = div(max(DateTime.diff(challenge.expires_at, DateTime.utc_now(), :millisecond), 0) + 999, 1000)

    if seconds > 0 do
      Process.send_after(self(), {:challenge_tick, token}, 1000)
    end

    {:noreply, assign(socket, seconds: seconds, state: if(seconds == 0, do: "expired", else: "pending"))}
  end

  def handle_info({:challenge_tick, _}, socket), do: {:noreply, socket}

  def handle_info({"reject", _}, %{assigns: %{challenge: %{outgoing: true}, current_player: player}} = socket) do
    player = Game.update_player!(player, %{last_challenge_at: nil})
    {:noreply, assign(socket, state: "declined", current_player: player)}
  end

  def handle_info({"reject", _}, socket), do: {:noreply, socket}

  def handle_info({"duel", %{id: id}}, socket) do
    {:noreply, redirect(socket, to: "/arena/#{id}")}
  end

  def handle_event("accept", _, %{assigns: %{challenge: %{outgoing: false} = challenge, state: "pending"}} = socket) do
    if DateTime.compare(DateTime.utc_now(), challenge.expires_at) == :lt do
      Game.create_duel!(challenge.other, socket.assigns.current_player)
      {:noreply, assign(socket, challenge: nil)}
    else
      {:noreply, assign(socket, state: "expired", seconds: 0)}
    end
  end

  def handle_event("accept", _, socket), do: {:noreply, socket}

  def handle_event("reject", _, %{assigns: %{challenge: %{outgoing: false} = challenge}} = socket) do
    MobaWeb.broadcast("player-#{challenge.other.id}", "reject", %{})
    {:noreply, assign(socket, challenge: nil)}
  end

  def handle_event("reject", _, socket), do: {:noreply, socket}
  def handle_event("close", _, socket), do: {:noreply, assign(socket, challenge: nil)}
end
