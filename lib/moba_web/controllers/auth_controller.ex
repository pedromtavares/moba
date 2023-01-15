defmodule MobaWeb.AuthController do
  use MobaWeb, :controller
  require Logger

  alias Moba.Accounts

  @discord_guild_id 656_676_554_994_352_128

  plug Ueberauth

  def start(conn, params) do
    conn
    |> put_session(:origin, origin_for(conn, params["origin"]))
    |> redirect(to: "/auth/discord")
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user = conn.assigns.current_player.user

    Accounts.update_user!(user, %{discord: basic_info(auth)})
    Accounts.create_unlock!(user, "tinker")
    origin = get_session(conn, :origin)

    resp =
      Nostrum.Api.add_guild_member(
        @discord_guild_id,
        String.to_integer(auth.uid),
        access_token: auth.credentials.token,
        nick: user.username
      )

    IO.inspect(resp)

    conn
    |> put_session(:origin, nil)
    |> redirect(to: origin || origin_for(conn, nil))
  end

  defp basic_info(auth) do
    %{id: auth.uid, nickname: auth.info.nickname, avatar: auth.info.image, token: auth.credentials.token}
  end

  defp origin_for(conn, param) do
    case param do
      "tavern" -> "/tavern"
      _ -> "/player/#{conn.assigns.current_player.id}"
    end
  end
end
