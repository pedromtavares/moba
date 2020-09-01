defmodule MobaWeb.AuthHelper do
  @moduledoc """
  Helper to set the current user id in session, used by most LiveViews
  """
  import Plug.Conn

  def init(_) do
  end

  def call(conn, _) do
    user = conn.assigns.current_user

    conn
    |> put_session(:user_id, user.id)
  end
end
