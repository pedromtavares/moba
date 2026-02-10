defmodule MobaWeb.V2.Hooks.RequireAuth do
  @moduledoc """
  on_mount hook that ensures a player_id exists in the session.
  Redirects to /start if not authenticated.
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, %{"player_id" => player_id}, socket) when is_integer(player_id) do
    {:cont, socket}
  end

  def on_mount(:default, _params, _session, socket) do
    {:halt, redirect(socket, to: "/start")}
  end
end
