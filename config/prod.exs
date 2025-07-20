import Config

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Aveline.Finch

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

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
  dsn: "https://0ffae7310c5a87bd1f4fd8361a83ddaa@o4509698496397312.ingest.us.sentry.io/4509699399155712",
  environment_name: "prod",
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]
