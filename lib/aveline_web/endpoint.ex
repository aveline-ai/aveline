defmodule AvelineWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :aveline
  use Sentry.PlugCapture

  @session_options Aveline.Config.session_options!()

  # LiveView socket
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  plug Plug.Static,
    at: "/",
    from: :aveline,
    gzip: true,
    only: AvelineWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :aveline
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Sentry.PlugContext

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
