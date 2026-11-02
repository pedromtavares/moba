defmodule Moba.Repo do
  use Ecto.Repo,
    otp_app: :moba,
    adapter: Ecto.Adapters.Postgres,
    pool_size: 10

  @after_commit_key {__MODULE__, :after_commit}

  # Ecto's transaction/2 delegates to transact/2, so this also covers Multi and
  # nested domain transactions. Each level discards its notifications on failure.
  defoverridable transact: 2

  def transact(fun_or_multi, opts) do
    parent = Process.get(@after_commit_key)
    Process.put(@after_commit_key, [])

    {result, callbacks} =
      try do
        result = super(fun_or_multi, opts)
        {result, Process.get(@after_commit_key)}
      after
        if is_nil(parent),
          do: Process.delete(@after_commit_key),
          else: Process.put(@after_commit_key, parent)
      end

    case result do
      {:ok, _} ->
        if is_nil(parent),
          do: callbacks |> Enum.reverse() |> Enum.each(& &1.()),
          else: Process.put(@after_commit_key, callbacks ++ parent)

      _ ->
        :ok
    end

    result
  end

  @doc "Runs a notification after the outer transaction commits, or immediately outside a transaction."
  def after_commit(callback) when is_function(callback, 0) do
    case Process.get(@after_commit_key) do
      nil -> callback.()
      callbacks -> Process.put(@after_commit_key, [callback | callbacks])
    end

    :ok
  end

  def init(_type, config) do
    {:ok, Keyword.put(config, :url, System.get_env("DATABASE_URL"))}
  end
end
