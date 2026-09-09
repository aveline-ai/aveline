//// DataSources IO capabilities. Built for real in
//// lib/aveline/gleam/caps/data_sources.ex; keep the two in lockstep
//// (tag + field order).
////
//// Secrets never become Gleam values with structure: `Secret` is an
//// opaque external type the controller threads straight through to the
//// cap closure, and query rows (`QueryResult`) are free-form JSON that
//// passes through opaquely (per the porting conventions).

import aveline/data_sources/data_source_info.{type DataSourceInfo}
import gleam/option.{type Option}

/// A customer-database password, opaque to Gleam. At runtime this is the
/// raw Elixir binary; only cap closures ever look inside.
pub type Secret

/// Ad-hoc query result — the free-form columns/rows map the runner
/// produces, echoed to the caller untouched.
pub type QueryResult

pub type DsWriteError {
  /// Unique-constraint conflict on (workspace, name).
  DsNameTaken
  /// The Elixir context refused the write with a coded error — echoed
  /// verbatim so the wire behavior can't drift even if pure validation
  /// and the context ever disagree.
  DsRejected(code: String, message: String)
}

pub type DataSourcesCaps {
  DataSourcesCaps(
    /// Live sources for a workspace, ordered by name.
    list_for_workspace: fn(String) -> List(DataSourceInfo),
    /// Live current version by (workspace_id, name).
    get_current_by_name: fn(String, String) -> Option(DataSourceInfo),
    /// Create: (workspace_id, name, template, password, user_id).
    create: fn(String, String, String, Secret, String) ->
      Result(DataSourceInfo, DsWriteError),
    /// Versioned edit: (data_source_id, name, template, password
    /// (None keeps the stored secret), user_id). Supersedes + scrubs the
    /// old row in one transaction, Elixir-side.
    edit: fn(String, String, String, Option(Secret), String) ->
      Result(DataSourceInfo, DsWriteError),
    /// Run SQL against the built-in catalog: (workspace_id, sql).
    run_catalog_query: fn(String, String) -> Result(QueryResult, String),
    /// Run SQL against an external source: (data_source_id, sql). The
    /// closure re-reads the row so the credential never leaves Elixir.
    run_source_query: fn(String, String) -> Result(QueryResult, String),
    /// Soft-delete the row + hard-delete its secret: (id, user_id).
    soft_delete: fn(String, String) -> Nil,
  )
}

pub fn stub() -> DataSourcesCaps {
  DataSourcesCaps(
    list_for_workspace: fn(_) { panic as "stub data_sources.list_for_workspace" },
    get_current_by_name: fn(_, _) {
      panic as "stub data_sources.get_current_by_name"
    },
    create: fn(_, _, _, _, _) { panic as "stub data_sources.create" },
    edit: fn(_, _, _, _, _) { panic as "stub data_sources.edit" },
    run_catalog_query: fn(_, _) {
      panic as "stub data_sources.run_catalog_query"
    },
    run_source_query: fn(_, _) { panic as "stub data_sources.run_source_query" },
    soft_delete: fn(_, _) { panic as "stub data_sources.soft_delete" },
  )
}
