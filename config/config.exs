# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :moba,
  ecto_repos: [Moba.Repo],
  env: Mix.env(),
  admin_refresh_seconds: System.get_env("ADMIN_REFRESH_SECONDS") || "1000000000"

# Configures the endpoint
config :moba, MobaWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "alj84Hk7zalGeRCGYyMcQCZh9LQcTVls6lEG/lXXgC7xC9c3HsFjSrAFd0MMhDxO2",
  render_errors: [view: MobaWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: Moba.PubSub,
  live_view: [
    signing_salt: "0rCmKQt21BmJfTqBwGVEaIm/AY2dnbry"
  ]

config :torch,
  otp_app: :moba,
  template_format: "eex"

config :moba, :pow,
  user: Moba.Accounts.Schema.User,
  repo: Moba.Repo,
  web_module: MobaWeb,
  extensions: [PowResetPassword, PowPersistentSession],
  # extensions: [PowResetPassword, PowEmailConfirmation],
  controller_callbacks: MobaWeb.PowControllerCallbacks,
  mailer_backend: MobaWeb.PowMailer,
  web_mailer_module: MobaWeb,
  routes_backend: MobaWeb.PowRoutes,
  cache_store_backend: Pow.Postgres.Store

config :pow, Pow.Postgres.Store, repo: Moba.Repo

config :moba, MobaWeb.PowMailer, adapter: Bamboo.LocalAdapter

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
