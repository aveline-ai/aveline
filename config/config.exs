# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.

import Config

# Data source secrets must never reach logs or error reports: filter the
# create/edit params (password is Phoenix's default; url carries the
# template which is safe, but filter it anyway — defense in depth).
config :phoenix, :filter_parameters, ["password", "url", "token", "secret"]

config :aveline,
  env: config_env(),
  ecto_repos: [Aveline.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true],
  landing_page_url: "https://aveline.ai"

config :aveline, Aveline.Repo,
  migration_timestamps: [type: :timestamptz],
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id]

# Endpoint
config :aveline, AvelineWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AvelineWeb.ErrorHTML, json: AvelineWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Aveline.PubSub,
  live_view: [signing_salt: "aveline-lv-salt-change-me-in-prod"]

# Timezones
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Mailer
config :aveline, Aveline.Mailer, adapter: Swoosh.Adapters.Local

# Logger — stdout, captured by Fly.
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Sentry — compile-time defaults. DSN + enable_logs are set in config/runtime.exs
# only if SENTRY_DSN is present (so the app is a no-op locally when no DSN).
config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

# Oban — basic config; queues empty for v0.
config :aveline, Oban,
  repo: Aveline.Repo,
  plugins: [{Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60, interval: 24 * 60 * 60_000}],
  queues: []

# esbuild — bundles assets/js/app.js → priv/static/assets/js/app.js
config :esbuild,
  version: "0.25.4",
  aveline: [
    args:
      ~w(js/app.js js/echarts-loader.js js/sqlformatter-loader.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]
    }
  ]

import_config "#{config_env()}.exs"
