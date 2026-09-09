//// Types crossing the coarse doc-write caps (create / replace_blocks /
//// apply_ops / restore). Block and op payloads stay opaque `Dynamic`
//// values — the block engine is not ported; Gleam never inspects them.

import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}

/// Metadata for creating a doc. Blocks/tags payloads travel alongside as
/// opaque values.
pub type CreateAttrs {
  CreateAttrs(
    workspace_id: String,
    owner_id: String,
    actor_user_id: String,
    actor_type: String,
    title: Option(String),
    slug: Option(String),
    summary: Option(String),
    intent: Option(String),
    visibility: String,
  )
}

/// Metadata for shipping a new version. `None` fields keep the current
/// value. `resolves`/`dispositions` are opaque payloads for the comment
/// disposition gate on the Elixir side.
pub type UpdateAttrs {
  UpdateAttrs(
    actor_user_id: String,
    actor_type: String,
    title: Option(String),
    summary: Option(String),
    tags: Option(Dynamic),
    intent: Option(String),
    resolves: Dynamic,
    dispositions: Dynamic,
  )
}

/// The minimal pointer a write echoes so the agent can chain calls.
pub type DocPointer {
  DocPointer(
    slug: String,
    doc_id: String,
    version_id: String,
    version_number: Int,
  )
}

pub type WriteFailure {
  /// A bare-message block/op validation failure — the handler appends
  /// the `aveline contract` hint before surfacing it.
  BlockInvalid(message: String)
  /// Any other write error (changesets, disposition tuples, …), passed
  /// through to the FallbackController unchanged.
  OtherFailure(reason: Dynamic)
}

pub type RestoredDoc {
  RestoredDoc(slug: String, doc_id: String, version_number: Int)
}

pub type RestoreFailure {
  RestoreNotFound
  RestoreNotUserDeleted
}
