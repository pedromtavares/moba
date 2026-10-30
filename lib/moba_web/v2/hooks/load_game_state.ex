defmodule MobaWeb.V2.Hooks.LoadGameState do
  @moduledoc """
  on_mount hook that loads the current player and hero into assigns.
  Subscribes to player-level PubSub topic when connected.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias Moba.{Accounts, Game}
  import MobaWeb.Preview, only: [preview_path: 2]

  def on_mount(:default, _params, %{"player_id" => player_id} = session, socket) do
    %{assigns: %{current_player: player}} =
      socket =
      assign_new(socket, :current_player, fn ->
        Game.get_player!(player_id)
      end)

    if player do
      player.user && Accounts.set_online_now(player.user)

      socket =
        socket
        |> assign_new(:current_hero, fn -> player.current_pve_hero end)
        |> maybe_subscribe(player)
        |> maybe_handle_duel_messages(session["preview"])

      {:cont, socket}
    else
      {:halt, redirect(socket, to: preview_path(socket, "/start"))}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    {:halt, redirect(socket, to: preview_path(socket, "/start"))}
  end

  defp maybe_subscribe(socket, player) do
    if connected?(socket) do
      MobaWeb.subscribe("player-#{player.id}")
    end

    socket
  end

  defp maybe_handle_duel_messages(socket, true) do
    attach_hook(socket, :duel_challenge_messages, :handle_info, fn
      {event, _}, socket when event in ["challenge", "reject", "duel"] -> {:halt, socket}
      _, socket -> {:cont, socket}
    end)
  end

  defp maybe_handle_duel_messages(socket, _), do: socket
end
