defmodule Moba.MixProject do
  use Mix.Project

  def project do
    [
      app: :moba,
      version: "0.1.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Moba.Application, []},
      extra_applications: [:logger, :runtime_tools, :timex, :mnesia]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.6.6"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:ecto_sql, "~> 3.0"},
      {:ecto_psql_extras, "~> 0.6"},
      {:postgrex, ">= 0.15.3"},
      {:phoenix_html, "~> 3.2"},
      {:phoenix_live_reload, "~> 1.3.3", only: :dev},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.1"},
      {:plug_cowboy, "~> 2.2"},
      {:mix_test_watch, "~> 0.6", only: :dev, runtime: false},
      {:arc, "~> 0.11.0"},
      {:arc_ecto, "~> 0.11.1"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:sweet_xml, "~> 0.7"},
      {:phoenix_live_view, "~> 0.17.7", override: true},
      {:torch, "~> 4.1.0"},
      {:distillery, "~> 2.1", runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:timex, "~> 3.5"},
      {:pow, "~> 1.0.20"},
      {:bamboo, "~> 1.3"},
      {:hackney, ">= 1.15.2"},
      {:faker, "~> 0.13"},
      {:elixir_uuid, "~> 1.2"},
      {:cachex, "~> 3.3"},
      {:phoenix_live_dashboard, "~> 0.5"},
      {:telemetry_poller, "~> 0.4"},
      {:telemetry_metrics, "~> 0.6"},
      {:ecto_explain, "~> 0.1.2"},
      {:sentry, "~> 8.0"},
      {:appsignal, "~> 2.0"},
      {:appsignal_phoenix, "~> 2.0"},
      {:pow_postgres_store, github: "ZennerIoT/pow_postgres_store"},
      {:floki, ">= 0.0.0", only: :test},
      {:credo, "~> 1.5.0-rc.2", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      seed_test: ["ecto.setup", "test"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
end
