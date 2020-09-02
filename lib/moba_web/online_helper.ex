defmodule MobaWeb.OnlineHelper do
  @moduledoc """
  Plug that updates the user with the current time, to help visualize who is online
  """
  def init(opts), do: opts

  def call(conn, _) do
    user = conn.assigns.current_user

    user && Moba.Accounts.set_user_online_now(user)

    conn
  end
end
