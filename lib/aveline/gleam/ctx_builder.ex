defmodule Aveline.Gleam.CtxBuilder do
  @moduledoc """
  Builds the Gleam `Ctx` capability record (src/aveline/core/ctx.gleam)
  and the `Scope` for a conn.

  Gleam records are tagged tuples. Each domain's caps are built by its
  own module under Aveline.Gleam.Caps.* — that module and its Gleam twin
  in src/aveline/caps/<domain>.gleam must agree on tag + field order and
  are owned together. This file mirrors ctx.gleam's field order and is
  STABLE shared surface: do not reorder while porting a domain.

  Conventions at the boundary:
    * Gleam Option: `{:some, value}` | `:none` (Aveline.Gleam.Interop).
    * Gleam custom-type constructors: snake_cased atom tags,
      e.g. `WorkspaceVisible` -> `:workspace_visible`.
    * Caps raise on genuine DB failure (Repo.insert!/delete!), surfacing
      as 500s exactly as the pre-Gleam code did.
  """

  alias Aveline.Gleam.Caps

  def build do
    {:ctx, Caps.Comments.build(), Caps.DataSources.build(), Caps.Docs.build(),
     Caps.Events.build(), Caps.Keys.build(), Caps.Kudos.build(), Caps.Milestones.build(),
     Caps.Queries.build(), Caps.Tags.build(), Caps.Team.build(), Caps.Views.build(),
     Caps.Workspaces.build()}
  end

  # Scope from conn assigns set by ApiAuth + WorkspaceScope plugs.
  def scope(conn) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    {:scope, {:workspace, ws.id, ws.slug}, {:actor, user.id, user.username}}
  end
end
