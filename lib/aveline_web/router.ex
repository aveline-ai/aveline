defmodule AvelineWeb.Router do
  use AvelineWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
  end

  # Public routes (accessible to everyone)
  scope "/", AvelineWeb do
    pipe_through [:api]

    get "/", PingController, :ping
    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/logout", AuthController, :logout
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:aveline, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
