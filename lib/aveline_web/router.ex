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

  pipeline :workspace_gate do
    plug AvelineWeb.Plugs.WorkspaceGate
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
  end

  # Workspace-scoped pages sit behind the access gate: non-members (and
  # unfurl bots) get a branded private page AT the URL instead of a
  # redirect to signup. See Plugs.WorkspaceGate.
  scope "/", AvelineWeb do
    pipe_through [:browser, :workspace_gate]

    live "/w/:slug", HomeLive, :index
    live "/w/:slug/docs", WorkspaceShowLive, :index
    live "/w/:slug/v/:view_name", WorkspaceShowLive, :view
    live "/w/:slug/d/:doc_slug", DocShowLive, :show
    live "/w/:slug/d/:doc_slug/v/:version", DocShowLive, :show_version
    live "/w/:slug/activity", ActivityLive, :index
    # Usage merged into Team; old links land on the Team page.
    get "/w/:slug/usage", RedirectController, :team
    live "/w/:slug/data-sources", DataSourcesLive, :index
    # Per-source detail pages folded into the Data sources page (query
    # modal + source filter); old links land on the list.
    get "/w/:slug/data-sources/:name", RedirectController, :data_sources
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
    get "/keys", KeyController, :index
    post "/keys", KeyController, :create
    delete "/keys/:id", KeyController, :delete
    get "/contract", ContractController, :show
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

    # Doc permissions v1: visibility in place, per-member shares.
    put "/docs/:doc_slug/visibility", DocController, :set_visibility
    get "/docs/:doc_slug/shares", DocController, :shares
    post "/docs/:doc_slug/shares", DocController, :share
    delete "/docs/:doc_slug/shares/:username", DocController, :unshare

    # Doc versions
    get "/docs/:doc_slug/versions", VersionController, :index
    get "/docs/:doc_slug/versions/:version_number", VersionController, :show

    # Run one chart block and get its rows (reads return config only).
    post "/docs/:doc_slug/blocks/:block_id/run", DocController, :run_block

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
    get "/views", ViewController, :index
    post "/views", ViewController, :create
    patch "/views/:name", ViewController, :update
    put "/views/:name", ViewController, :update
    delete "/views/:name", ViewController, :delete
    post "/views/:name/restore", ViewController, :restore
    post "/views/:name/pin", ViewController, :pin
    delete "/views/:name/pin", ViewController, :unpin

    # View buckets: the space a view lives in, and the unit views are
    # shared at.
    get "/view-buckets", ViewController, :buckets
    post "/view-buckets", ViewController, :create_bucket
    delete "/view-buckets/:bucket_name", ViewController, :delete_bucket
    put "/view-buckets/:bucket_name/visibility", ViewController, :set_bucket_visibility
    post "/view-buckets/:bucket_name/members", ViewController, :add_bucket_member
    delete "/view-buckets/:bucket_name/members/:username", ViewController, :remove_bucket_member
    put "/views/:name/bucket", ViewController, :move

    # Timeline milestones — dated facts overlaid on time-series charts.
    get "/milestones", MilestoneController, :index
    post "/milestones", MilestoneController, :create
    delete "/milestones/:id", MilestoneController, :delete

    get "/data-sources", DataSourceController, :index
    post "/data-sources", DataSourceController, :create
    patch "/data-sources/:name", DataSourceController, :update
    put "/data-sources/:name", DataSourceController, :update
    post "/data-sources/:name/query", DataSourceController, :query
    delete "/data-sources/:name", DataSourceController, :delete

    # Query catalog — named, versioned queries built on data sources.
    # `source` filter on index gives the per-source lineage view.
    get "/queries", QueryController, :index
    post "/queries", QueryController, :create
    get "/queries/:name", QueryController, :show
    patch "/queries/:name", QueryController, :update
    put "/queries/:name", QueryController, :update
    delete "/queries/:name", QueryController, :delete
    post "/queries/:name/restore", QueryController, :restore

    get "/tags", TagController, :index
    post "/tags", TagController, :create
    get "/tags/:slug", TagController, :show
    patch "/tags/:slug", TagController, :update
    put "/tags/:slug", TagController, :update
    delete "/tags/:slug", TagController, :delete
    post "/tags/:slug/restore", TagController, :restore

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
