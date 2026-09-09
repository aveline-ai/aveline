//// Data-sources-domain test fixtures, plus unsafe-but-typed builders
//// for the opaque boundary types (Secret / QueryResult) that only exist
//// as raw Elixir values in production.

import aveline/caps/data_sources.{
  type DataSourcesCaps, type QueryResult, type Secret,
}
import aveline/data_sources/data_source_info.{
  type DataSourceInfo, DataSourceInfo, Live,
}
import gleam/option.{type Option}

pub fn source(name name: String, adapter adapter: String) -> DataSourceInfo {
  DataSourceInfo(
    id: "ds-1",
    name: name,
    adapter: adapter,
    url: "postgres://u:<password>@h/db",
    version_number: 1,
    credential: Live,
    deleted: False,
    created_at: "2026-09-01T00:00:00Z",
  )
}

pub fn sources_returning(found: Option(DataSourceInfo)) -> DataSourcesCaps {
  data_sources.DataSourcesCaps(
    ..data_sources.stub(),
    get_current_by_name: fn(_, _) { found },
  )
}

@external(erlang, "gleam_stdlib", "identity")
pub fn secret(value: String) -> Secret

@external(erlang, "gleam_stdlib", "identity")
pub fn query_result(value: String) -> QueryResult
