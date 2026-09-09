//// /queries — the workspace query catalog. Ports QueryController's six
//// actions plus the decision logic of Aveline.DataSources.Queries:
//// name/description normalization, changeset-parity validation,
//// reference and cycle checks, dependent protection, versioned edits,
//// soft delete and restore. Heavy IO (list SQL, SQL parsing, the graph
//// lock, inserts) stays behind caps.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Invalid, NotFound}
import aveline/core/scope.{type Scope}
import aveline/queries/query.{
  type Kind, type Query, Derived, NewQuery, Raw, SourceRef, VersionAttrs,
}
import aveline/queries/rules
import aveline/queries/validate
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type CreateRequest {
  CreateRequest(
    name: String,
    sql: String,
    description: Option(String),
    /// A data source name; its presence makes the query raw, its
    /// absence derived.
    source: Option(String),
  )
}

pub type EditRequest {
  EditRequest(
    new_name: Option(String),
    sql: Option(String),
    /// Outer None = field absent from the body; inner is its value
    /// (an explicit null clears the description).
    description: Option(Option(String)),
  )
}

/// GET /queries[?source=name] — the whole catalog, or the lineage view
/// of queries built on one source (unknown source lists nothing).
pub fn index(
  ctx: Ctx,
  scope: Scope,
  source: Option(String),
) -> Result(List(Query), ApiError) {
  case source {
    None -> Ok(ctx.queries.list_for_workspace(scope.workspace.id))
    Some(source_name) ->
      case ctx.queries.get_source_by_name(scope.workspace.id, source_name) {
        None -> Ok([])
        Some(SourceRef(base_id, _)) ->
          Ok(ctx.queries.list_for_source(scope.workspace.id, base_id))
      }
  }
}

/// GET /queries/:name
pub fn show(ctx: Ctx, scope: Scope, name: String) -> Result(Query, ApiError) {
  case ctx.queries.get_current_by_name(scope.workspace.id, name) {
    None -> Error(NotFound)
    Some(query) -> Ok(query)
  }
}

/// POST /queries
pub fn create(
  ctx: Ctx,
  scope: Scope,
  request: CreateRequest,
) -> Result(Query, ApiError) {
  let name = validate.normalize_name(request.name)
  let description = validate.normalize_description(request.description)

  case request.source {
    None -> create_derived(ctx, scope, name, description, request.sql)
    Some(source_name) ->
      case ctx.queries.get_source_by_name(scope.workspace.id, source_name) {
        None ->
          Error(Invalid(
            "data_source_not_found",
            "no data source named \"" <> source_name <> "\"",
          ))
        Some(SourceRef(_, True)) ->
          Error(Invalid(
            "invalid_query",
            "raw queries target external sources; a query over the workspace catalog is a derived query (omit source)",
          ))
        Some(SourceRef(base_id, False)) ->
          insert(ctx, scope, name, description, Raw, Some(base_id), request.sql)
      }
  }
}

/// PATCH/PUT /queries/:name — versioned edit; any of new_name,
/// description, sql. Renames are rejected while other derived queries
/// reference the old name.
pub fn update(
  ctx: Ctx,
  scope: Scope,
  name_param: String,
  request: EditRequest,
) -> Result(Query, ApiError) {
  let workspace_id = scope.workspace.id
  use current <- result.try(show(ctx, scope, name_param))

  let name =
    validate.normalize_name(option.unwrap(request.new_name, current.name))
  let sql = option.unwrap(request.sql, current.sql)
  let description = case request.description {
    Some(value) -> validate.normalize_description(value)
    None -> current.description
  }

  ctx.queries.with_graph_lock(workspace_id, fn() {
    use _ <- result.try(case name != current.name {
      True -> no_derived_dependents(ctx, workspace_id, current.name, "rename")
      False -> Ok(Nil)
    })
    use _ <- result.try(validate_for_kind(ctx, workspace_id, current, name, sql))
    use _ <- result.try(validate_insert(name, sql))

    ctx.queries.insert_next_version(
      workspace_id,
      current,
      VersionAttrs(name: name, description: description, sql: sql),
      scope.actor.id,
    )
    |> result.map_error(invalid_query)
  })
}

/// DELETE /queries/:name — soft delete; rejected while other derived
/// queries reference it.
pub fn delete(ctx: Ctx, scope: Scope, name: String) -> Result(Nil, ApiError) {
  let workspace_id = scope.workspace.id
  use current <- result.try(show(ctx, scope, name))

  ctx.queries.with_graph_lock(workspace_id, fn() {
    use _ <- result.try(no_derived_dependents(
      ctx,
      workspace_id,
      current.name,
      "delete",
    ))
    Ok(ctx.queries.soft_delete(current.id, scope.actor.id))
  })
  |> result.replace(Nil)
}

/// POST /queries/:name/restore — undelete; fails if the name was
/// re-taken.
pub fn restore(
  ctx: Ctx,
  scope: Scope,
  name: String,
) -> Result(Query, ApiError) {
  case ctx.queries.get_latest_deleted_by_name(scope.workspace.id, name) {
    None -> Error(NotFound)
    Some(current) ->
      ctx.queries.restore(current.id) |> result.map_error(invalid_query)
  }
}

// ── internals ──────────────────────────────────────────────────────

fn create_derived(
  ctx: Ctx,
  scope: Scope,
  name: String,
  description: Option(String),
  sql: String,
) -> Result(Query, ApiError) {
  let workspace_id = scope.workspace.id

  ctx.queries.with_graph_lock(workspace_id, fn() {
    use refs <- result.try(parse(ctx, sql))
    use _ <- result.try(refs_resolve(ctx, workspace_id, refs, name, None))
    use _ <- result.try(stays_dag(ctx, workspace_id, None, name, refs))
    insert(ctx, scope, name, description, Derived, None, sql)
  })
}

/// Raw edits skip parsing (the SQL is the source's dialect); derived
/// edits re-validate references and acyclicity with the old name
/// swapped out.
fn validate_for_kind(
  ctx: Ctx,
  workspace_id: String,
  current: Query,
  new_name: String,
  sql: String,
) -> Result(Nil, ApiError) {
  case current.kind {
    Raw -> Ok(Nil)
    Derived -> {
      use refs <- result.try(parse(ctx, sql))
      use _ <- result.try(refs_resolve(
        ctx,
        workspace_id,
        refs,
        new_name,
        Some(current.name),
      ))
      stays_dag(ctx, workspace_id, Some(current.name), new_name, refs)
    }
  }
}

fn insert(
  ctx: Ctx,
  scope: Scope,
  name: String,
  description: Option(String),
  kind: Kind,
  data_source_id: Option(String),
  sql: String,
) -> Result(Query, ApiError) {
  use _ <- result.try(validate_insert(name, sql))

  ctx.queries.insert(
    scope.workspace.id,
    NewQuery(
      name: name,
      description: description,
      kind: kind,
      data_source_id: data_source_id,
      sql: sql,
      created_by_id: scope.actor.id,
    ),
  )
  |> result.map_error(invalid_query)
}

fn parse(ctx: Ctx, sql: String) -> Result(List(String), ApiError) {
  ctx.queries.parse(sql) |> result.map_error(invalid_query)
}

fn refs_resolve(
  ctx: Ctx,
  workspace_id: String,
  refs: List(String),
  own_name: String,
  except: Option(String),
) -> Result(Nil, ApiError) {
  let live_names =
    ctx.queries.list_for_workspace(workspace_id)
    |> list.map(fn(q) { q.name })

  rules.refs_resolve(live_names, refs, own_name, except)
  |> result.map_error(invalid_query)
}

fn stays_dag(
  ctx: Ctx,
  workspace_id: String,
  except: Option(String),
  name: String,
  refs: List(String),
) -> Result(Nil, ApiError) {
  rules.stays_dag(ctx.queries.derived_edges(workspace_id), except, name, refs)
  |> result.map_error(invalid_query)
}

fn no_derived_dependents(
  ctx: Ctx,
  workspace_id: String,
  name: String,
  action: String,
) -> Result(Nil, ApiError) {
  rules.no_derived_dependents(
    ctx.queries.derived_edges(workspace_id),
    name,
    action,
  )
  |> result.map_error(fn(message) { Invalid("query_has_dependents", message) })
}

fn validate_insert(name: String, sql: String) -> Result(Nil, ApiError) {
  validate.validate_insert(name, sql) |> result.map_error(invalid_query)
}

fn invalid_query(message: String) -> ApiError {
  Invalid("invalid_query", message)
}
