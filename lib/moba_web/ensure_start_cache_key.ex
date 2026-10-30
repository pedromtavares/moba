defmodule MobaWeb.EnsureStartCacheKey do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :cache_key) do
      conn
    else
      put_session(conn, :cache_key, UUID.uuid1())
    end
  end
end
