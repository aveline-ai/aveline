//// Queries IO capabilities. Built for real in
//// lib/aveline/gleam/caps/queries.ex; keep the two in lockstep
//// (tag + field order).

import aveline/core/error.{type ApiError}
import aveline/queries/query.{
  type NewQuery, type Query, type SourceRef, type VersionAttrs,
}
import gleam/option.{type Option}

pub type QueriesCaps {
  QueriesCaps(
    /// Live (non-superseded, non-deleted) queries, ordered by name.
    list_for_workspace: fn(String) -> List(Query),
    /// Live queries bound to one source: (workspace_id, source_base_id).
    list_for_source: fn(String, String) -> List(Query),
    /// Current live query by name: (workspace_id, name).
    get_current_by_name: fn(String, String) -> Option(Query),
    /// Current soft-deleted query by name — for restore.
    get_latest_deleted_by_name: fn(String, String) -> Option(Query),
    /// Live data source by name, as the queries domain sees it.
    get_source_by_name: fn(String, String) -> Option(SourceRef),
    /// Parse derived SQL (analytics dialect) -> sorted table refs, or
    /// the engine's message (syntax error, non-SELECT, …).
    parse: fn(String) -> Result(List(String), String),
    /// Every live derived query's (name, parsed refs) in a workspace;
    /// stored SQL that no longer parses contributes no edges.
    derived_edges: fn(String) -> List(#(String, List(String))),
    /// Run the thunk inside a transaction holding the per-workspace
    /// query-graph advisory lock; an Error rolls the transaction back.
    with_graph_lock: fn(String, fn() -> Result(Query, ApiError)) ->
      Result(Query, ApiError),
    /// Insert version 1: (workspace_id, attrs). Error is the changeset
    /// message (uniqueness etc.) — product behavior, handlers map it.
    insert: fn(String, NewQuery) -> Result(Query, String),
    /// Supersede `current` and insert the next version:
    /// (workspace_id, current, attrs, user_id).
    insert_next_version: fn(String, Query, VersionAttrs, String) ->
      Result(Query, String),
    /// Soft-delete by id: (query_id, user_id) -> updated query.
    soft_delete: fn(String, String) -> Query,
    /// Clear deleted_at by id; Error is the changeset message when the
    /// name was re-taken.
    restore: fn(String) -> Result(Query, String),
  )
}

pub fn stub() -> QueriesCaps {
  QueriesCaps(
    list_for_workspace: fn(_) { panic as "stub queries.list_for_workspace" },
    list_for_source: fn(_, _) { panic as "stub queries.list_for_source" },
    get_current_by_name: fn(_, _) { panic as "stub queries.get_current_by_name" },
    get_latest_deleted_by_name: fn(_, _) {
      panic as "stub queries.get_latest_deleted_by_name"
    },
    get_source_by_name: fn(_, _) { panic as "stub queries.get_source_by_name" },
    parse: fn(_) { panic as "stub queries.parse" },
    derived_edges: fn(_) { panic as "stub queries.derived_edges" },
    with_graph_lock: fn(_, _) { panic as "stub queries.with_graph_lock" },
    insert: fn(_, _) { panic as "stub queries.insert" },
    insert_next_version: fn(_, _, _, _) {
      panic as "stub queries.insert_next_version"
    },
    soft_delete: fn(_, _) { panic as "stub queries.soft_delete" },
    restore: fn(_) { panic as "stub queries.restore" },
  )
}
