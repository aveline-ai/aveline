import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :aveline, Aveline.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "aveline_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :aveline, AvelineWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "XBXzJBJn2ZLvEcJ9YqUj17gLi9uwQ72pPOeOcvcQxch4PC7so2Er83kIndEJLszD",
  server: false

config :aveline,
  client_base_url: "http://localhost:5173",
  session_options: [
    store: :cookie,
    key: "_aveline_key",
    signing_salt: "D5I5dAJs",
    same_site: "None",
    secure: true,
    max_age: 60 * 60 * 24 * 365
  ]

# In test we don't send emails
config :aveline, Aveline.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
