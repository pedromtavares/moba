defmodule Moba.MixProject do
  use Mix.Project

  def project do
    [
      app: :moba,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
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
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_live_view, "~> 1.1.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.3.3", only: :dev},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.15.3"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.1"},
      {:bandit, "~> 1.5"},
      {:mix_test_watch, "~> 0.6", only: :dev, runtime: false},
      {:waffle, "~> 1.1.9"},
      {:waffle_ecto, "~> 0.0.12"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:sweet_xml, "~> 0.7"},
      {:torch, "~> 6.0.0"},
      {:distillery, "~> 2.1", runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:timex, "~> 3.5"},
      {:swoosh, "~> 1.4"},
      {:hackney, ">= 1.15.2"},
      {:faker, "~> 0.13"},
      {:elixir_uuid, "~> 1.2"},
      {:cachex, "~> 3.3"},
      {:telemetry_poller, "~> 0.4"},
      {:telemetry_metrics, "~> 0.6"},
      {:sentry, "~> 11.0.4"},
      {:ueberauth_discord, "~> 0.6"},
      {:nostrum, github: "Kraigie/nostrum", runtime: Mix.env() == :prod},
      {:cowlib, "~> 2.11", hex: :remedy_cowlib, override: true},
      {:gun, "2.0.1", hex: "remedy_gun", override: true},
      {:floki, ">= 0.36.2", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:credo, "~> 1.5.0-rc.2", only: [:dev, :test], runtime: false},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:dns_cluster, "~> 0.2.0"},
      {:req, "~> 0.5"}
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
