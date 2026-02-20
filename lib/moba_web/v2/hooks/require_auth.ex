defmodule MobaWeb.V2.Hooks.RequireAuth do
  @moduledoc """
  on_mount hook that ensures the user is authenticated via user_token.
  Delegates to MobaWeb.UserAuth.on_mount/4 which redirects to the login page
  if no valid session token is found.
  """

  def on_mount(:default, params, session, socket) do
    MobaWeb.UserAuth.on_mount(:ensure_authenticated, params, session, socket)
  end
end
