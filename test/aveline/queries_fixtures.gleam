//// Queries-domain test fixtures.

import aveline/caps/queries.{type QueriesCaps, QueriesCaps}
import aveline/queries/query.{type Query, Derived, Query, Raw}
import gleam/option.{type Option, None, Some}

pub fn raw_query(name name: String) -> Query {
  Query(
    id: "q-" <> name,
    base_query_id: "base-" <> name,
    version_number: 1,
    name: name,
    description: None,
    kind: Raw,
    data_source_id: Some("src-base-1"),
    sql: "select 1 as n",
    deleted: False,
    created_at: "2026-01-01T00:00:00.000000Z",
  )
}

pub fn derived_query(name name: String, sql sql: String) -> Query {
  Query(..raw_query(name: name), kind: Derived, data_source_id: None, sql: sql)
}

/// A caps record whose graph lock is a pass-through — the shape almost
/// every write test wants; override the rest per test.
pub fn caps() -> QueriesCaps {
  QueriesCaps(..queries.stub(), with_graph_lock: fn(_, thunk) { thunk() })
}

/// Caps for a catalog with fixed live queries and derived edges — the
/// common read surface of the write paths.
pub fn catalog(
  live live: List(Query),
  edges edges: List(#(String, List(String))),
) -> QueriesCaps {
  QueriesCaps(
    ..caps(),
    list_for_workspace: fn(_) { live },
    derived_edges: fn(_) { edges },
  )
}

pub fn returning(query: Option(Query)) -> QueriesCaps {
  QueriesCaps(..caps(), get_current_by_name: fn(_, _) { query })
}
