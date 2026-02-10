defmodule MobaWeb.V2.Hooks.LoadGameState do
  @moduledoc """
  on_mount hook that loads the current player and hero into assigns.
  Subscribes to PubSub for real-time updates when connected.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias Moba.{Accounts, Game}

  def on_mount(:default, _params, %{"player_id" => player_id}, socket) do
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

      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/start")}
    end
  end

  defp maybe_subscribe(socket, player) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Moba.PubSub, "player:#{player.id}")
    end

    socket
  end
end
