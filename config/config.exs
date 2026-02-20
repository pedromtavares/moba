# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :moba,
  ecto_repos: [Moba.Repo],
  env: Mix.env(),
  admin_refresh_seconds: System.get_env("ADMIN_REFRESH_SECONDS") || "1000000000",
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :moba, MobaWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  secret_key_base: "alj84Hk7zalGeRCGYyMcQCZh9LQcTVls6lEG/lXXgC7xC9c3HsFjSrAFd0MMhDxO2",
  render_errors: [formats: [html: MobaWeb.ErrorView, json: MobaWeb.ErrorView], layout: false],
  pubsub_server: Moba.PubSub,
  live_view: [
    signing_salt: "0rCmKQt21BmJfTqBwGVEaIm/AY2dnbry"
  ]

config :ueberauth, Ueberauth,
  providers: [
    discord: {Ueberauth.Strategy.Discord, [default_scope: "identify email guilds.join"]}
  ]

config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: System.get_env("DISCORD_CLIENT_ID"),
  client_secret: System.get_env("DISCORD_CLIENT_SECRET")

config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN")

config :torch,
  otp_app: :moba,
  template_format: "eex"


config :moba, Moba.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Esbuild configuration for v2 asset pipeline (JS only, Tailwind handles CSS)
config :esbuild,
  version: "0.25.0",
  v2: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/v2/assets --external:/fonts/* --external:/images/* --external:/v2/*),
    cd: Path.expand("../assets_v2", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Tailwind configuration for v2 asset pipeline
config :tailwind,
  version: "4.1.7",
  v2: [
    args: ~w(
      --input=assets_v2/css/app.css
      --output=priv/static/v2/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
