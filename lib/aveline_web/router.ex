defmodule AvelineWeb.Router do
  use AvelineWeb, :router

  import AvelineWeb.Auth,
    only: [
      plug_put_current_user_from_session: 2,
      plug_redirect_if_logged_out: 2,
      plug_redirect_if_logged_in: 2
    ]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AvelineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :plug_put_current_user_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes (accessible to everyone)
  scope "/", AvelineWeb do
    pipe_through :browser

    get "/ping", PageController, :ping
  end

  # Guest-only routes (redirect if logged in)
  scope "/", AvelineWeb do
    pipe_through [:browser, :plug_redirect_if_logged_in]

    get "/login/:code", SessionController, :login_with_code
  end

  # Protected routes (must be logged in)
  scope "/", AvelineWeb do
    pipe_through [:browser, :plug_redirect_if_logged_out]

    get "/logout", SessionController, :logout

    live "/", HomeLive
    live "/chat", ChatLive
    live "/learn", LearnLive
  end

  scope "/admin" do
    pipe_through [:browser, :plug_redirect_if_not_admin]
  end

  # Other scopes may use custom stacks.
  # scope "/api", AvelineWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:aveline, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AvelineWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
