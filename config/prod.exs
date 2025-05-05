import Config

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Aveline.Finch

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

config :aveline, AvelineWeb.Endpoint,
  check_origin: ["https://app.aveline.ai"],
  client_base_url: "https://app.aveline.ai"
