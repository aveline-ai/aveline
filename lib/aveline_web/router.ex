defmodule AvelineWeb.Router do
  use AvelineWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AvelineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug :accepts, ["json"]
    plug AvelineWeb.Plugs.ApiAuth
  end

  pipeline :workspace_scoped do
    plug AvelineWeb.Plugs.WorkspaceScope
  end

  # ===== Browser routes =====

  scope "/", AvelineWeb do
    pipe_through :browser

    live "/signup", SignupLive, :index
    live "/login", LoginLive, :index
    live "/invite/:code", InviteLive, :index
    get "/login/:token", SessionController, :create
    post "/login", SessionController, :create
    get "/logout", SessionController, :delete

    live "/", WorkspaceListLive, :index
    live "/w/:slug", WorkspaceShowLive, :index
    live "/w/:slug/i/:item_slug", ItemShowLive, :show
    live "/w/:slug/views", ViewListLive, :index
    live "/w/:slug/v/:view_slug", ViewShowLive, :show
    live "/w/:slug/team", TeamLive, :index
    live "/w/:slug/settings", SettingsLive, :index
  end

  # ===== Open API =====

  scope "/api", AvelineWeb.Api do
    pipe_through :api

    get "/heartbeat", HeartbeatController, :show
  end

  # ===== Authed API =====

  scope "/api", AvelineWeb.Api do
    pipe_through :api_auth

    get "/me", MeController, :show
    get "/workspaces", WorkspaceController, :index
    get "/workspaces/:slug", WorkspaceController, :show
  end

  scope "/api/workspaces/:workspace_slug", AvelineWeb.Api do
    pipe_through [:api_auth, :workspace_scoped]

    get "/items", ItemController, :index
    post "/items", ItemController, :create
    get "/items/:item_slug", ItemController, :show
    patch "/items/:item_slug", ItemController, :update
    put "/items/:item_slug", ItemController, :update
    delete "/items/:item_slug", ItemController, :delete
    post "/items/:item_slug/restore", ItemController, :restore

    get "/items/:item_slug/messages", MessageController, :index
    post "/items/:item_slug/messages", MessageController, :create
    patch "/items/:item_slug/messages/:id", MessageController, :update
    put "/items/:item_slug/messages/:id", MessageController, :update
    delete "/items/:item_slug/messages/:id", MessageController, :delete

    get "/views", ViewController, :index
    post "/views", ViewController, :create
    get "/views/:view_slug", ViewController, :show
    patch "/views/:view_slug", ViewController, :update
    put "/views/:view_slug", ViewController, :update
    delete "/views/:view_slug", ViewController, :delete
  end

  if Application.compile_env(:aveline, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
