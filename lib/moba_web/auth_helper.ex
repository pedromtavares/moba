defmodule MobaWeb.AuthHelper do
  @moduledoc """
  Helper to set the current user id in session, used by most LiveViews
  """
  import Plug.Conn

  def init(_) do
  end

  def call(%{assigns: %{current_user: current_user}} = conn, _) when not is_nil(current_user) do
    put_session(conn, :user_id, current_user.id)
  end
  def call(conn, _), do: conn
end
