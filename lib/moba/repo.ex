defmodule Moba.Repo do
  use Ecto.Repo,
    otp_app: :moba,
    adapter: Ecto.Adapters.Postgres,
    pool_size: 10

  use Ecto.Explain

  def init(_type, config) do
    {:ok, Keyword.put(config, :url, System.get_env("DATABASE_URL"))}
  end

  def reload(%module{id: id}) do
    get(module, id)
  end
end
