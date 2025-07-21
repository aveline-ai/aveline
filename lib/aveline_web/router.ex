defmodule AvelineWeb.Router do
  use AvelineWeb, :router

  import AvelineWeb.AuthPlug,
    only: [put_current_user_from_session: 2, require_authenticated_user: 2, require_no_authenticated_user: 2]

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :put_current_user_from_session
  end

  # Authless Routes (works for both logged in and logged out users)
  scope "/", AvelineWeb do
    pipe_through [:api]
    get "/", PingController, :ping
    get "/error", PingController, :error
    post "/jobs/test-success", PingController, :test_job
    post "/jobs/test-error", PingController, :test_error_job
  end

  ## Authenticated Routes (you must be logged in to access these routes)
  scope "/", AvelineWeb do
    pipe_through [:api, :require_authenticated_user]

    get "/current-user", AuthController, :current_user
    post "/logout", AuthController, :logout
  end

  # Unauthenticated Routes (you must be logged out to access these routes)
  scope "/", AvelineWeb do
    pipe_through [:api, :require_no_authenticated_user]

    post "/register", AuthController, :register
    post "/login", AuthController, :login
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:aveline, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
