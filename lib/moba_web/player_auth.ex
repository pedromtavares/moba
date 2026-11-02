defmodule MobaWeb.PlayerAuth do
  import Phoenix.Controller
  import Plug.Conn

  def init(_) do
  end

  def call(conn, _) do
    current_user = conn.assigns[:current_user]
    player_id = get_session(conn, :player_id)
    player = player_id && Moba.Repo.get(Moba.Game.Schema.Player, player_id)

    cond do
      current_user && (!player || player.user_id != current_user.id) ->
        player = Moba.player_for(current_user)

        conn
        |> put_session(:player_id, player.id)
        |> assign(:current_player, player)

      player && (is_nil(player.user_id) || (current_user && player.user_id == current_user.id)) ->
        assign(conn, :current_player, Moba.Game.get_player!(player.id))

      player && player.user_id ->
        conn |> delete_session(:player_id) |> redirect(to: "/users/log_in") |> halt()

      true ->
        conn |> redirect(to: MobaWeb.Preview.preview_path(conn, "/start")) |> halt()
    end
  end
end
