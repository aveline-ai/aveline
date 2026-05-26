import Config

config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Aveline.Finch
config :swoosh, local: false

config :logger, level: :info

# Runtime production configuration (DB url, secret key base, host, sentry dsn)
# is in config/runtime.exs and pulled from environment variables / Fly secrets.

config :aveline,
  client_base_url: "https://app.aveline.ai",
  session_options: [
    store: :cookie,
    key: "_aveline_key",
    signing_salt: "D5I5dAJs",
    same_site: "Lax",
    domain: ".aveline.ai",
    secure: true,
    max_age: 60 * 60 * 24 * 365
  ]

config :sentry,
  environment_name: "prod",
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  integrations: [
    oban: [
      capture_errors: true,
      cron: [enabled: true]
    ]
  ]
