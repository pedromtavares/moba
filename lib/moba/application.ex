defmodule Moba.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # "redis://redis-rofs:10000"
    redis_uri = System.get_env("REDIS_URI") || "redis://localhost:6379"
    # List all child processes to be supervised
    children = [
      # Start the Ecto repository
      Moba.Repo,
      MobaWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Moba.PubSub},
      # Start the endpoint when the application starts
      MobaWeb.Endpoint,
      # Cache for hero creation
      {Cachex, name: :game_cache},
      # Redix for persistent sessions
      {Redix, {redis_uri, [name: :redix]}},
      # Starts a worker by calling: Moba.Worker.start_link(arg)
      # {Moba.Worker, arg},
      Moba.Game.Server,
      Moba.Admin.Server
    ]

    :telemetry.attach(
      "appsignal-ecto",
      [:moba, :repo, :query],
      &Appsignal.Ecto.handle_event/4,
      nil
    )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Moba.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    MobaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
