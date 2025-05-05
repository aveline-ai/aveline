defmodule AvelineWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :aveline

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_aveline_key",
    signing_salt: "D5I5dAJs",
    same_site: "None",
    secure: true
  ]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :aveline,
    gzip: true,
    only: AvelineWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :aveline
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  plug Corsica,
    origins: [Aveline.Config.client_base_url!()],
    allow_credentials: true,
    max_age: 600,
    allow_methods: :all,
    allow_headers: :all

  plug Plug.Session, @session_options
  plug AvelineWeb.Router
end
