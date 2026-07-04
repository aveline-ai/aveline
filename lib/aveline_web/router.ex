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
    live "/w/:slug", HomeLive, :index
    live "/w/:slug/docs", WorkspaceShowLive, :index
    live "/w/:slug/board", BoardLive, :index
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
    post "/workspaces", WorkspaceController, :create
    get "/workspaces/:slug", WorkspaceController, :show
  end

  scope "/api/workspaces/:workspace_slug", AvelineWeb.Api do
    pipe_through [:api_auth, :workspace_scoped]

    # Docs
    get "/orientation", DocController, :orientation
    get "/docs", DocController, :index
    post "/docs", DocController, :create
    get "/docs/:doc_slug", DocController, :show
    patch "/docs/:doc_slug", DocController, :update
    put "/docs/:doc_slug", DocController, :update
    delete "/docs/:doc_slug", DocController, :delete
    post "/docs/:doc_slug/restore", DocController, :restore
    post "/docs/:doc_slug/kudos", DocController, :kudos

    # Home-page pin slots
    post "/docs/:doc_slug/pin", DocController, :pin
    delete "/docs/:doc_slug/pin", DocController, :unpin

    # Doc versions
    get "/docs/:doc_slug/versions", VersionController, :index
    get "/docs/:doc_slug/versions/:version_number", VersionController, :show

    # Comments
    get "/docs/:doc_slug/comments", CommentController, :index
    post "/docs/:doc_slug/comments", CommentController, :create
    patch "/comments/:id", CommentController, :update
    put "/comments/:id", CommentController, :update
    delete "/comments/:id", CommentController, :delete
    post "/comments/:id/undelete", CommentController, :undelete
    post "/comments/:id/resolve", CommentController, :resolve
    post "/comments/:id/unresolve", CommentController, :unresolve

    # Tags
    get "/tags", TagController, :index
    post "/tags", TagController, :create
    get "/tags/:slug", TagController, :show
    patch "/tags/:slug", TagController, :update
    put "/tags/:slug", TagController, :update
    delete "/tags/:slug", TagController, :delete

    # Team / members
    get "/members", TeamController, :index
    post "/members", TeamController, :add
    delete "/members/:user_id", TeamController, :remove

    # Invite link
    post "/invite", TeamController, :invite
    delete "/invite", TeamController, :revoke_invite

    # Activity events
    get "/events", EventController, :index
  end

  if Application.compile_env(:aveline, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
