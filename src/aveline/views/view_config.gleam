//// Incoming view-config payloads and their validation. The controller
//// converts the raw JSON map into `ConfigParam` mechanically (present /
//// null / string / wrong-type per key); every decision — shape rules,
//// tag existence, group_by scope — lives here.
////
//// Ports Aveline.Views.validate_config_against_workspace plus the View
//// changeset's validate_config, preserving check ORDER (context checks
//// run before changeset shape checks) so error codes come out the same.
//// Edits MERGE onto the current config: absent keys keep their value,
//// explicit nulls clear.

import aveline/core/error.{type ApiError, Invalid}
import aveline/views/model.{type ViewConfig, ViewConfig}
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type RawField {
  Absent
  Null
  RawString(String)
  /// Present but not a string.
  BadField
}

pub type RawTags {
  TagsAbsent
  TagsList(List(String))
  /// Present but not a clean list of strings; carries whatever string
  /// entries it did contain (the legacy code still checks those for
  /// existence before rejecting the shape).
  TagsInvalid(List(String))
}

pub type RawConfig {
  RawConfig(
    tags: RawTags,
    group_by: RawField,
    sub_group_by: RawField,
    edited: RawField,
    sort: RawField,
    icon: RawField,
  )
}

pub type ConfigParam {
  /// No config in the request: create validates an empty config, edit
  /// re-validates the current one unchanged (as before).
  NoConfig
  NotAnObject
  ConfigObject(RawConfig)
}

pub fn empty_raw() -> RawConfig {
  RawConfig(
    tags: TagsAbsent,
    group_by: Absent,
    sub_group_by: Absent,
    edited: Absent,
    sort: Absent,
    icon: Absent,
  )
}

/// Merge `param` onto `base` and validate the whole result. `unknown_tags`
/// returns the subset of the given slugs not defined in the workspace;
/// `scope_has_tags` says whether a scope has members.
pub fn apply_and_validate(
  base: ViewConfig,
  param: ConfigParam,
  unknown_tags: fn(List(String)) -> List(String),
  scope_has_tags: fn(String) -> Bool,
) -> Result(ViewConfig, ApiError) {
  case param {
    NotAnObject -> Error(Invalid("view_invalid", "config must be an object"))
    NoConfig -> validate(base, empty_raw(), unknown_tags, scope_has_tags)
    ConfigObject(raw) -> validate(base, raw, unknown_tags, scope_has_tags)
  }
}

type Merged {
  MNone
  MSome(String)
  MBad
}

fn merge_field(base: Option(String), raw: RawField) -> Merged {
  case raw {
    Absent ->
      case base {
        Some(v) -> MSome(v)
        None -> MNone
      }
    Null -> MNone
    RawString(s) -> MSome(s)
    BadField -> MBad
  }
}

fn validate(
  base: ViewConfig,
  raw: RawConfig,
  unknown_tags: fn(List(String)) -> List(String),
  scope_has_tags: fn(String) -> Bool,
) -> Result(ViewConfig, ApiError) {
  let #(tags, tags_shape_ok) = case raw.tags {
    TagsAbsent -> #(base.tags, True)
    TagsList(l) -> #(l, True)
    TagsInvalid(strings) -> #(strings, False)
  }
  let group_by = merge_field(base.group_by, raw.group_by)
  let sub_group_by = merge_field(base.sub_group_by, raw.sub_group_by)
  let edited = merge_field(base.edited, raw.edited)
  let sort = merge_field(base.sort, raw.sort)
  let icon = merge_field(base.icon, raw.icon)

  // Context-stage checks first (tag existence, group_by scope) —
  // they outrank the changeset's shape checks, as before the port.
  use _ <- result.try(case unknown_tags(tags) {
    [] -> Ok(Nil)
    _ ->
      Error(Invalid(
        "unknown_tags",
        "One or more tags aren't defined in this workspace yet. Create them first.",
      ))
  })
  use group_by <- result.try(check_group_by(group_by, scope_has_tags))
  // Changeset-stage shape checks, in the changeset's order.
  use <- bool.guard(
    !tags_shape_ok,
    Error(Invalid("validation_failed", "tags must be a list of tag slugs")),
  )
  use sub_group_by <- result.try(check_sub_group_by(sub_group_by))
  use _ <- result.try(case sub_group_by {
    None -> Ok(Nil)
    Some(s) ->
      case group_by {
        Some(g) if g != s -> Ok(Nil)
        _ ->
          Error(Invalid(
            "validation_failed",
            "sub_group_by needs a different group_by scope",
          ))
      }
  })
  use edited <- result.try(check_edited(edited))
  use sort <- result.try(check_sort(sort))
  use icon <- result.try(check_icon(icon))
  Ok(ViewConfig(tags:, group_by:, sub_group_by:, edited:, sort:, icon:))
}

fn check_group_by(
  merged: Merged,
  scope_has_tags: fn(String) -> Bool,
) -> Result(Option(String), ApiError) {
  let shape_error =
    Invalid(
      "view_invalid",
      "group_by must be a tag scope (a plain slug like \"status\")",
    )
  case merged {
    MNone -> Ok(None)
    MBad -> Error(shape_error)
    MSome(s) ->
      case is_scope_slug(s) {
        False -> Error(shape_error)
        True ->
          case scope_has_tags(s) {
            True -> Ok(Some(s))
            False ->
              Error(Invalid(
                "view_invalid",
                "group_by scope has no tags in this workspace: " <> s,
              ))
          }
      }
  }
}

// The context's `^[a-z0-9][a-z0-9-]*$` (no length cap, unlike slugs).
fn is_scope_slug(s: String) -> Bool {
  case string.to_graphemes(s) {
    [] -> False
    [first, ..rest] ->
      is_alnum(first) && list.all(rest, fn(c) { is_alnum(c) || c == "-" })
  }
}

fn is_alnum(c: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyz0123456789", c)
}

fn check_sub_group_by(merged: Merged) -> Result(Option(String), ApiError) {
  case merged {
    MNone -> Ok(None)
    MBad | MSome("") ->
      Error(Invalid(
        "validation_failed",
        "sub_group_by must be a tag scope or null",
      ))
    MSome(s) -> Ok(Some(s))
  }
}

fn check_edited(merged: Merged) -> Result(Option(String), ApiError) {
  let err =
    Invalid(
      "validation_failed",
      "edited must be a window like \"7d\" or \"24h\" (max 365d)",
    )
  case merged {
    MNone -> Ok(None)
    MBad -> Error(err)
    MSome(s) ->
      case normalize_within(s) {
        Some(token) -> Ok(Some(token))
        None -> Error(err)
      }
  }
}

/// Ports Aveline.Docs.normalize_within: `^(\d{1,4})(h|d)$` on the
/// trimmed value, capped at 365 days, leading zeros dropped.
pub fn normalize_within(v: String) -> Option(String) {
  let t = string.trim(v)
  let unit = string.slice(t, string.length(t) - 1, 1)
  let digits = string.drop_end(t, 1)
  let digits_ok =
    string.length(digits) >= 1
    && string.length(digits) <= 4
    && list.all(string.to_graphemes(digits), fn(c) {
      string.contains("0123456789", c)
    })
  case digits_ok && { unit == "h" || unit == "d" } {
    False -> None
    True ->
      case int.parse(digits) {
        Error(_) -> None
        Ok(n) -> {
          let hours = case unit {
            "d" -> n * 24
            _ -> n
          }
          case hours >= 1 && hours <= 365 * 24 {
            True -> Some(int.to_string(n) <> unit)
            False -> None
          }
        }
      }
  }
}

fn check_sort(merged: Merged) -> Result(Option(String), ApiError) {
  let err = Invalid("validation_failed", "sort must be one of recent, title")
  case merged {
    MNone -> Ok(None)
    MBad -> Error(err)
    MSome(s) ->
      case s == "recent" || s == "title" {
        True -> Ok(Some(s))
        False -> Error(err)
      }
  }
}

fn check_icon(merged: Merged) -> Result(Option(String), ApiError) {
  case merged {
    MNone -> Ok(None)
    MBad -> Error(Invalid("validation_failed", "icon must be a string"))
    MSome(s) -> Ok(Some(s))
  }
}
