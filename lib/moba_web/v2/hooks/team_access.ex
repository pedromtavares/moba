defmodule MobaWeb.V2.Hooks.TeamAccess do
  @moduledoc "Session ownership for public team training, including unclaimed guests."
  import Phoenix.LiveView
  import Phoenix.Component

  def authorize(session) do
    player = session["player_id"] && Moba.Repo.get(Moba.Game.Schema.Player, session["player_id"])
    user = session["user_token"] && Moba.Accounts.get_user_by_session_token(session["user_token"])

    cond do
      player && user && player.user_id == user.id -> %{user: user, player_id: player.id}
      player && is_nil(player.user_id) && is_nil(user) -> %{user: nil, player_id: player.id}
      true -> nil
    end
  end

  def on_mount(:default, _, session, socket) do
    case authorize(session) do
      nil ->
        # /start has no player until the full roster is submitted.
        if socket.view == MobaWeb.V2.DraftLive && is_nil(session["player_id"]) && is_nil(session["user_token"]),
          do: {:cont, assign(socket, current_scope: %{user: nil}, access_session: session)},
          else: {:halt, redirect(socket, to: "/")}

      scope ->
        {:cont,
         socket
         |> assign(current_scope: scope, access_session: session)
         |> assign_new(:current_player, fn -> Moba.Game.get_player!(scope.player_id) end)
         |> assign_new(:current_hero, fn -> nil end)
         |> attach_hook(:team_session, :handle_event, fn _, _, socket ->
           if current = authorize(session),
             do: {:cont, assign(socket, :current_scope, current)},
             else: {:halt, redirect(socket, to: "/")}
         end)}
    end
  end
end
