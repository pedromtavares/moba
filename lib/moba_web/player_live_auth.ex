defmodule MobaWeb.PlayerLiveAuth do
  import Phoenix.LiveView
  alias Moba.{Accounts, Game}

  def on_mount(:default, _params, %{"player_id" => player_id} = _session, socket) do
    %{assigns: %{current_player: player}} =
      socket =
      assign_new(socket, :current_player, fn ->
        Game.get_player!(player_id)
      end)

    if player do
      player.user && Accounts.set_online_now(player.user)

      socket =
        assign_new(socket, :current_hero, fn ->
          player.current_pve_hero
        end)

      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/start")}
    end
  end
end
