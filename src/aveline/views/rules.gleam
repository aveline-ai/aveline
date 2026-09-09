//// Pure view/bucket decision rules: bucket audiences, reserved names,
//// slug-name and description validation. Ports the cond/branch logic of
//// Aveline.Views + the View/Bucket changeset checks that decide API
//// behavior.

import aveline/core/error.{type ApiError, Invalid}
import aveline/views/model.{
  type Bucket, Personal, Private, Project, Team, WorkspaceVisible,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Is `user_id` in this bucket's audience? (Workspace membership is
/// already checked by the plugs.) `member_bucket_ids` is the user's live
/// project-bucket memberships.
pub fn in_audience(
  bucket: Bucket,
  user_id: String,
  member_bucket_ids: List(String),
) -> Bool {
  case bucket.visibility {
    WorkspaceVisible -> True
    Private ->
      case bucket.kind {
        Personal -> bucket.owner_id == Some(user_id)
        Project ->
          bucket.owner_id == Some(user_id)
          || list.contains(member_bucket_ids, bucket.id)
        // Unreachable: team buckets are always workspace-visible.
        Team -> False
      }
  }
}

/// "team" and "personal-*" are minted by the system, never by hand.
pub fn reserved_bucket_name(name: String) -> Bool {
  name == "team" || string.starts_with(name, "personal-")
}

/// Names are stored trimmed + downcased (create path).
pub fn normalize_name(raw: String) -> String {
  raw |> string.trim |> string.lowercase
}

/// Slug format `[a-z0-9][a-z0-9-]*`, length 1-60 (Aveline.Slug).
pub fn is_slug(s: String) -> Bool {
  case string.to_graphemes(s) {
    [] -> False
    [first, ..rest] ->
      string.length(s) <= 60
      && is_alnum(first)
      && list.all(rest, fn(c) { is_alnum(c) || c == "-" })
  }
}

fn is_alnum(c: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyz0123456789", c)
}

/// View/bucket name validation (post-normalization).
pub fn validate_slug_name(name: String) -> Result(String, ApiError) {
  case name == "" {
    True -> Error(Invalid("validation_failed", "name can't be blank"))
    False ->
      case is_slug(name) {
        True -> Ok(name)
        False ->
          Error(Invalid(
            "validation_failed",
            "name must be a slug (lowercase letters, digits, dashes)",
          ))
      }
  }
}

/// Required, trimmed, 6-280 characters (the View changeset's rule).
pub fn validate_description(raw: Option(String)) -> Result(String, ApiError) {
  case raw {
    None -> Error(Invalid("validation_failed", "description can't be blank"))
    Some(d) -> {
      let d = string.trim(d)
      let len = string.length(d)
      case d {
        "" -> Error(Invalid("validation_failed", "description can't be blank"))
        _ if len < 6 ->
          Error(Invalid(
            "validation_failed",
            "description should be at least 6 characters",
          ))
        _ if len > 280 ->
          Error(Invalid(
            "validation_failed",
            "description should be at most 280 characters",
          ))
        _ -> Ok(d)
      }
    }
  }
}
