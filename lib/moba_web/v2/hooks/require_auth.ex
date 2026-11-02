defmodule MobaWeb.V2.Hooks.RequireAuth do
  @moduledoc """
  on_mount hook for v2 auth.

  A valid account token takes precedence over a guest player session.
  Guests without an authenticated account may access their unclaimed player.
  """

  import Phoenix.LiveView
  import Phoenix.Component
  alias Moba.{Accounts, Game}

  def on_mount(:default, _params, session, socket) do
    player_id = session["player_id"]
    player = player_id && Moba.Repo.get(Game.Schema.Player, player_id)
    token = session["user_token"]
    user = token && Accounts.get_user_by_session_token(token)

    cond do
      user && (!player || player.user_id != user.id) ->
        # A full request lets UserAuth repair the cookie session. LiveView cannot
        # replace a stale guest player_id stored in its signed session payload.
        {:halt, redirect(socket, to: "/base")}

      player && is_nil(player.user_id) ->
        socket =
          attach_hook(socket, :validate_guest_session, :handle_event, fn _, _, socket ->
            case Moba.Repo.get(Game.Schema.Player, player.id) do
              %{user_id: nil} -> {:cont, socket}
              _ -> {:halt, redirect(socket, to: "/users/log_in")}
            end
          end)

        {:cont, socket}

      player && user && player.user_id == user.id ->
        socket =
          socket
          |> assign(:current_user, user)
          |> attach_hook(:validate_game_session, :handle_event, fn _, _, socket ->
            case Accounts.get_user_by_session_token(token) do
              %{id: id} when id == user.id -> {:cont, socket}
              _ -> {:halt, redirect(socket, to: "/users/log_in")}
            end
          end)

        {:cont, socket}

      true ->
        {:halt, redirect(socket, to: "/users/log_in")}
    end
  end
end
