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

  # Every browser page is the Elm SPA shell; Elm routes client-side
  # (assets/src/Route.elm mirrors these paths — keep them in sync).
  scope "/", AvelineWeb do
    pipe_through :browser

    get "/signup", SpaController, :index
    get "/login", SpaController, :index
    get "/invite/:code", SpaController, :index
    get "/new-workspace", SpaController, :index
    get "/login/:token", SessionController, :create
    post "/login", SessionController, :create
    get "/logout", SessionController, :delete

    get "/", SpaController, :index
  end

  # Workspace-scoped pages sit behind the access gate: non-members (and
  # unfurl bots) get a branded private page AT the URL instead of a
  # redirect to signup. See Plugs.WorkspaceGate.
  scope "/", AvelineWeb do
    pipe_through [:browser, :workspace_gate]

    get "/w/:slug", SpaController, :index
    get "/w/:slug/welcome", SpaController, :index
    get "/w/:slug/docs", SpaController, :index
    get "/w/:slug/v/:view_name", SpaController, :index
    get "/w/:slug/d/:doc_slug", SpaController, :index
    get "/w/:slug/d/:doc_slug/v/:version", SpaController, :index
    get "/w/:slug/activity", SpaController, :index
    # Usage merged into Team; old links land on the Team page.
    get "/w/:slug/usage", RedirectController, :team
    get "/w/:slug/data-sources", SpaController, :index
    # Per-source detail pages folded into the Data sources page (query
    # modal + source filter); old links land on the list.
    get "/w/:slug/data-sources/:name", RedirectController, :data_sources
    get "/w/:slug/team", SpaController, :index
    get "/w/:slug/settings", SpaController, :index
  end

  # ===== Browser API (Elm SPA) =====
  #
  # Same controllers as /api, but the credential is the Phoenix session
  # cookie (BrowserApiAuth) with CSRF protection via the x-csrf-token
  # header. Keep this scope a route-for-route mirror of /api below.

  pipeline :papi do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  pipeline :papi_auth do
    plug AvelineWeb.Plugs.BrowserApiAuth
  end

  scope "/papi", AvelineWeb.Api do
    pipe_through :papi

    post "/session", SessionApiController, :create

    # fe-auth routes
    get "/signup/preview-token", SignupApiController, :preview_token
    get "/signup/username-status", SignupApiController, :username_status
    post "/signup", SignupApiController, :create
    get "/invites/:code", InviteApiController, :show
  end

  scope "/papi", AvelineWeb.Api do
    pipe_through [:papi, :papi_auth]

    delete "/session", SessionApiController, :delete
    get "/me", MeController, :show
    get "/keys", KeyController, :index
    post "/keys", KeyController, :create
    delete "/keys/:id", KeyController, :delete
    get "/workspaces", WorkspaceController, :index
    post "/workspaces", WorkspaceController, :create
    get "/workspaces/:slug", WorkspaceController, :show

    # fe-auth routes
    post "/invites/:code/accept", InviteApiController, :accept
  end

  scope "/papi/workspaces/:workspace_slug", AvelineWeb.Api do
    pipe_through [:papi, :papi_auth, :workspace_scoped]

    get "/orientation", DocController, :orientation
    get "/docs", DocController, :index
    post "/docs", DocController, :create
    get "/docs/:doc_slug", DocController, :show
    patch "/docs/:doc_slug", DocController, :update
    put "/docs/:doc_slug", DocController, :update
    delete "/docs/:doc_slug", DocController, :delete
    post "/docs/:doc_slug/restore", DocController, :restore
    post "/docs/:doc_slug/kudos", DocController, :kudos
    post "/docs/:doc_slug/pin", DocController, :pin
    delete "/docs/:doc_slug/pin", DocController, :unpin
    put "/docs/:doc_slug/visibility", DocController, :set_visibility
    get "/docs/:doc_slug/shares", DocController, :shares
    post "/docs/:doc_slug/shares", DocController, :share
    delete "/docs/:doc_slug/shares/:username", DocController, :unshare
    get "/docs/:doc_slug/versions", VersionController, :index
    get "/docs/:doc_slug/versions/:version_number", VersionController, :show
    post "/docs/:doc_slug/blocks/:block_id/run", DocController, :run_block
    get "/docs/:doc_slug/comments", CommentController, :index
    post "/docs/:doc_slug/comments", CommentController, :create
    patch "/comments/:id", CommentController, :update
    put "/comments/:id", CommentController, :update
    delete "/comments/:id", CommentController, :delete
    post "/comments/:id/undelete", CommentController, :undelete
    post "/comments/:id/resolve", CommentController, :resolve
    post "/comments/:id/unresolve", CommentController, :unresolve
    get "/views", ViewController, :index
    post "/views", ViewController, :create
    patch "/views/:name", ViewController, :update
    put "/views/:name", ViewController, :update
    delete "/views/:name", ViewController, :delete
    post "/views/:name/restore", ViewController, :restore
    post "/views/:name/pin", ViewController, :pin
    delete "/views/:name/pin", ViewController, :unpin
    get "/view-buckets", ViewController, :buckets
    post "/view-buckets", ViewController, :create_bucket
    delete "/view-buckets/:bucket_name", ViewController, :delete_bucket
    put "/view-buckets/:bucket_name/visibility", ViewController, :set_bucket_visibility
    post "/view-buckets/:bucket_name/members", ViewController, :add_bucket_member
    delete "/view-buckets/:bucket_name/members/:username", ViewController, :remove_bucket_member
    put "/views/:name/bucket", ViewController, :move
    get "/milestones", MilestoneController, :index
    post "/milestones", MilestoneController, :create
    delete "/milestones/:id", MilestoneController, :delete
    get "/data-sources", DataSourceController, :index
    post "/data-sources", DataSourceController, :create
    patch "/data-sources/:name", DataSourceController, :update
    put "/data-sources/:name", DataSourceController, :update
    post "/data-sources/:name/query", DataSourceController, :query
    delete "/data-sources/:name", DataSourceController, :delete
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
    get "/members", TeamController, :index
    post "/members", TeamController, :add
    delete "/members/:user_id", TeamController, :remove
    post "/invite", TeamController, :invite
    delete "/invite", TeamController, :revoke_invite
    get "/events", EventController, :index

    # fe-workspace routes
    get "/home", FeWorkspaceController, :home
    get "/welcome", FeWorkspaceController, :welcome
    get "/team", FeWorkspaceController, :team
    post "/invite/rotate", FeWorkspaceController, :rotate_invite
    put "/profile", FeWorkspaceController, :update_profile

    # fe-activity routes — SPA bootstrap for the Data sources page:
    # sources incl. soft-deleted, catalog with chart usage + lineage,
    # milestones. One roundtrip mirrors DataSourcesLive.mount/3.
    get "/data-sources-overview", DataSourceController, :overview

    # fe-docs-list routes
    # Elm Docs page reads: enriched doc list (card fields + has_more)
    # and corpus-wide facet counts for the filter dropdowns.
    get "/fe/docs-list", FeDocsController, :index
    get "/fe/docs-facets", FeDocsController, :facets

    # fe-doc-show routes — thin reads backing the Elm doc-show page
    # (AvelineWeb.Api.DocShowController). Browser-session surface only.
    get "/docs/:doc_slug/reader", DocShowController, :reader
    get "/docs/:doc_slug/kudos", DocShowController, :kudos_state
    get "/docs/:doc_slug/history", DocShowController, :history
    get "/docs/:doc_slug/versions/:version_number/comments", DocShowController, :version_comments
    post "/docs/:doc_slug/blocks/:block_id/rerun", DocShowController, :rerun_block
    # end fe-doc-show routes
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
