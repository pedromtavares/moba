use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :moba, MobaWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :moba, Moba.Repo,
  username: "postgres",
  password: "postgres",
  database: "moba_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :moba, MobaWeb.PowMailer, adapter: Bamboo.TestAdapter

config :pow, Pow.Ecto.Schema.Password, iterations: 1

config :arc,
  storage: Arc.Storage.Local

config :appsignal, :config, active: false
