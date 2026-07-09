import Config

config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Aveline.Finch
config :swoosh, local: false

config :logger, level: :info

# Runtime production configuration (DB url, secret key base, host, sentry dsn)
# is in config/runtime.exs and pulled from environment variables / Fly secrets.

# Session cookie scope is fixed at compile time. Self-hosted builds serve
# from a different hostname, where a cookie pinned to .aveline.ai is
# rejected by the browser (no session -> LiveView socket auth fails ->
# reload loop), so the Docker build can override these via build args.
# SESSION_COOKIE_DOMAIN="" means a host-only cookie (no domain attribute).
session_domain = System.get_env("SESSION_COOKIE_DOMAIN", ".aveline.ai")
session_secure? = System.get_env("SESSION_COOKIE_SECURE", "true") == "true"

config :aveline,
  client_base_url: "https://app.aveline.ai",
  session_options:
    [
      store: :cookie,
      key: "_aveline_key",
      signing_salt: "D5I5dAJs",
      same_site: "Lax",
      secure: session_secure?,
      max_age: 60 * 60 * 24 * 365
    ] ++ if(session_domain == "", do: [], else: [domain: session_domain])

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
