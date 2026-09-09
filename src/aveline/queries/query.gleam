//// Query catalog domain types (mirrors Aveline.DataSources.Query rows).
//// A query is config, never data: raw queries name an external source
//// and run in its dialect; derived queries compose other catalog
//// queries by name in the analytics dialect.

import gleam/option.{type Option}

pub type Kind {
  Raw
  Derived
}

pub type Query {
  Query(
    id: String,
    base_query_id: String,
    version_number: Int,
    name: String,
    description: Option(String),
    kind: Kind,
    /// Base id of the raw query's data source; None for derived.
    data_source_id: Option(String),
    sql: String,
    deleted: Bool,
    /// ISO8601 insertion timestamp (display value).
    created_at: String,
  )
}

/// A data source as the queries domain sees it: enough to bind a raw
/// query (base id) and to reject raw-over-the-workspace-source.
pub type SourceRef {
  SourceRef(base_data_source_id: String, workspace_builtin: Bool)
}

/// Attributes for a first-version insert.
pub type NewQuery {
  NewQuery(
    name: String,
    description: Option(String),
    kind: Kind,
    data_source_id: Option(String),
    sql: String,
    created_by_id: String,
  )
}

/// Attributes for a next-version insert (supersede current + insert).
pub type VersionAttrs {
  VersionAttrs(name: String, description: Option(String), sql: String)
}
