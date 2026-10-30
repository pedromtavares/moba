import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :moba, MobaWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Configure your database
config :moba, Moba.Repo,
  username: "postgres",
  password: "postgres",
  database: "moba_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :moba, Moba.Mailer, adapter: Swoosh.Adapters.Test


config :waffle,
  storage: Waffle.Storage.Local
