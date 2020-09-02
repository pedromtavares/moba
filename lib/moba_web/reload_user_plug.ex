defmodule MobaWeb.ReloadUserPlug do
  @moduledoc """
  Always fetches a fresh user record from the database instead of caching
  https://hexdocs.pm/pow/sync_user.html
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    config = Pow.Plug.fetch_config(conn)

    case Pow.Plug.current_user(conn, config) do
      nil ->
        conn

      user ->
        reloaded_user = Moba.Accounts.get_user!(user.id)

        Pow.Plug.assign_current_user(conn, reloaded_user, config)
    end
  end
end
