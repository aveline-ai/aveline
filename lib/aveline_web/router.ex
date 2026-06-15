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
    live "/new-workspace", WorkspaceNewLive, :new
    get "/login/:token", SessionController, :create
    post "/login", SessionController, :create
    get "/logout", SessionController, :delete

    live "/", SignupLive, :index
    live "/w/:slug", WorkspaceShowLive, :index
    live "/w/:slug/d/:doc_slug", DocShowLive, :show
    live "/w/:slug/d/:doc_slug/v/:version", DocShowLive, :show_version
    live "/w/:slug/activity", ActivityLive, :index
    live "/w/:slug/usage", UsageLive, :index
    live "/w/:slug/tags", TagsLive, :index
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

    get "/docs", DocController, :index
    post "/docs", DocController, :create
    get "/docs/:doc_slug", DocController, :show
    patch "/docs/:doc_slug", DocController, :update
    put "/docs/:doc_slug", DocController, :update
    delete "/docs/:doc_slug", DocController, :delete
    post "/docs/:doc_slug/restore", DocController, :restore
    post "/docs/:doc_slug/kudos", DocController, :kudos

    get "/docs/:doc_slug/comments", CommentController, :index
    post "/docs/:doc_slug/comments", CommentController, :create
    patch "/docs/:doc_slug/comments/:id", CommentController, :update
    put "/docs/:doc_slug/comments/:id", CommentController, :update
    delete "/docs/:doc_slug/comments/:id", CommentController, :delete

  end

  if Application.compile_env(:aveline, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
