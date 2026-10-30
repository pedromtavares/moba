defmodule Moba.Release do
  @moduledoc """
  Resource and bot maintenance for Mix tasks and assembled releases.

  Starts the repository and the bot notification dependencies, without starting
  the web endpoint, Discord consumer, or periodic maintenance workers.
  """

  alias Moba.{Conductor, Repo}

  def resources, do: with_repo(&Conductor.regenerate_resources!/0)

  def bots, do: with_repo(fn -> with_pubsub(&Conductor.regenerate_bots!/0) end)

  defp with_repo(fun) do
    Application.load(:moba)
    {:ok, result, _apps} = Ecto.Migrator.with_repo(Repo, fn _repo -> fun.() end, mode: :temporary)
    result
  end

  defp with_pubsub(fun) do
    if Process.whereis(Moba.PubSub) do
      fun.()
    else
      {:ok, _apps} = Application.ensure_all_started(:phoenix_pubsub)
      {:ok, supervisor} = Supervisor.start_link([{Phoenix.PubSub, name: Moba.PubSub}], strategy: :one_for_one)

      try do
        fun.()
      after
        Supervisor.stop(supervisor)
      end
    end
  end
end
