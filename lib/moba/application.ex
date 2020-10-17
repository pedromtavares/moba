defmodule Moba.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
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
      # Starts a worker by calling: Moba.Worker.start_link(arg)
      # {Moba.Worker, arg},
      Moba.Conductor,
      Moba.Admin.Server,
      {Pow.Postgres.Store.AutoDeleteExpired, [interval: :timer.hours(1)]}
    ]

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
