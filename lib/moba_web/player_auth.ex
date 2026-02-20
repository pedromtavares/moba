defmodule MobaWeb.PlayerAuth do
  import Phoenix.Controller
  import Plug.Conn

  def init(_) do
  end

  def call(conn, _) do
    current_user = conn.assigns[:current_user]
    player_id = get_session(conn, :player_id)
    player = player_id && Moba.Game.get_player!(player_id)

    cond do
      current_user && !player_id ->
        player = Moba.player_for(current_user)

        conn
        |> put_session(:player_id, player.id)
        |> assign(:current_player, player)

      player_id ->
        assign(conn, :current_player, player)

      true ->
        conn |> redirect(to: "/start") |> halt()
    end
  end
end
