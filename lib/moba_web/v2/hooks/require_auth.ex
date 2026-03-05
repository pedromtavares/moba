defmodule MobaWeb.V2.Hooks.RequireAuth do
  @moduledoc """
  on_mount hook for v2 auth.

  Guests with a `player_id` session are allowed.
  Otherwise, fallback to regular authenticated-user checks.
  """

  def on_mount(:default, _params, %{"player_id" => _player_id}, socket) do
    {:cont, socket}
  end

  def on_mount(:default, params, session, socket) do
    MobaWeb.UserAuth.on_mount(:ensure_authenticated, params, session, socket)
  end
end
