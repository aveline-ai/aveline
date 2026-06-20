import Config

# Database. Pulled from DATABASE_URL if set, otherwise falls back to
# localhost defaults. Provider-agnostic — anything that speaks Postgres
# works (managed services, RDS, local docker, etc.). Set DATABASE_URL
# in your .env to point at a remote DB.
config :aveline, Aveline.Repo,
  username: System.get_env("PGUSER") || "postgres",
  password: System.get_env("PGPASSWORD") || "postgres",
  hostname: System.get_env("PGHOST") || "localhost",
  database: System.get_env("PGDATABASE") || "aveline_dev",
  url: System.get_env("DATABASE_URL"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :aveline, AvelineWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "7H/trW1vBKZbfFFfgcoBGfneWKA9UAUXUNFSHLmUDJD2NzNYrMqI7nRZLuzWQVmp",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:aveline, ~w(--sourcemap=inline --watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/aveline_web/router\.ex$",
      ~r"lib/aveline_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :aveline,
  client_base_url: "http://localhost:4000",
  session_options: [
    store: :cookie,
    key: "_aveline_key",
    signing_salt: "D5I5dAJs",
    same_site: "Lax",
    secure: false,
    max_age: 60 * 60 * 24 * 365
  ]

config :aveline, dev_routes: true

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :swoosh, :api_client, false

# Sentry DSN is read from SENTRY_DSN in config/runtime.exs (works in both dev and prod).
# In dev it's optional — if unset, Sentry simply no-ops.
config :sentry,
  environment_name: "dev",
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  integrations: [
    oban: [
      capture_errors: true,
      cron: [enabled: true]
    ]
  ]
