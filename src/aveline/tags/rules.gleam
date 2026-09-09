//// Pure tag rules — slug format, field validation, and the scoped-tag
//// (`scope:value`) enum semantics. Ports the decision logic from
//// Aveline.Tags / Aveline.Tags.Tag / Aveline.Slug.
////
//// Error mapping mirrors the legacy changeset summary exactly:
////   * malformed slug        -> Invalid("tag_invalid", ...)
////   * every other field     -> Invalid("validation_failed", "Validation failed.")
//// A malformed slug wins over other field errors, like the changeset
//// summary's cond did.

import aveline/core/error.{type ApiError, Invalid}
import aveline/tags/tag.{type TagFields, TagFields}
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const min_description = 6

pub const max_description = 280

const max_slug_part = 60

// ===== Normalization =====

pub fn normalize_slug(raw: String) -> String {
  raw |> string.trim |> string.lowercase
}

pub fn normalize_color(raw: String) -> String {
  raw |> string.trim |> string.lowercase
}

// ===== Slug format =====

/// One slug half: `[a-z0-9][a-z0-9-]*`, length 1-60 (Aveline.Slug.validate).
pub fn valid_slug_part(part: String) -> Bool {
  case string.to_graphemes(part) {
    [] -> False
    [first, ..rest] ->
      string.length(part) <= max_slug_part
      && is_slug_char(first)
      && list.all(rest, fn(c) { is_slug_char(c) || c == "-" })
  }
}

fn is_slug_char(c: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyz0123456789", c)
}

/// Plain tag (`runbook`) or scoped tag (`status:todo`) — one `:` max,
/// both halves ordinary slugs.
pub fn valid_tag_slug(slug: String) -> Bool {
  case string.split(slug, ":") {
    [plain] -> valid_slug_part(plain)
    [scope, value] -> valid_slug_part(scope) && valid_slug_part(value)
    _ -> False
  }
}

// ===== Colors =====

/// A normalized color must be `#` + six lowercase hex digits.
pub fn valid_color(color: String) -> Bool {
  case string.to_graphemes(color) {
    ["#", ..digits] ->
      list.length(digits) == 6
      && list.all(digits, fn(c) { string.contains("0123456789abcdef", c) })
    _ -> False
  }
}

// ===== Field validation =====

/// Validate + normalize the full field set for a tag row. `slug` must
/// already be normalized (trim + lowercase); `description` and `color`
/// are normalized here. `sort_key` is free-form.
pub fn validate_fields(
  slug: String,
  description: String,
  color: Option(String),
  sort_key: Option(String),
) -> Result(TagFields, ApiError) {
  let description = string.trim(description)

  use <- bool.guard(
    slug != "" && !valid_tag_slug(slug),
    Error(Invalid(
      "tag_invalid",
      "Tag slug must be lowercase letters, digits, hyphens.",
    )),
  )
  use <- bool.guard(slug == "", validation_failed())
  use <- bool.guard(
    string.length(description) < min_description
      || string.length(description) > max_description,
    validation_failed(),
  )

  case color {
    None -> Ok(TagFields(slug:, description:, color: None, sort_key:))
    Some(raw) -> {
      let color = normalize_color(raw)
      case valid_color(color) {
        True ->
          Ok(TagFields(slug:, description:, color: Some(color), sort_key:))
        False -> validation_failed()
      }
    }
  }
}

fn validation_failed() -> Result(a, ApiError) {
  Error(Invalid("validation_failed", "Validation failed."))
}

// ===== Scoped tags =====
// A tag slug of the form `scope:value` (e.g. `status:todo`) is an enum
// member: a doc's tag set may carry at most one tag per scope. Plain
// tags are unaffected. The scope lives in the slug — no extra state.

/// The scope of a scoped tag — Some("status") for "status:todo"; None
/// for plain tags.
pub fn scope_of(slug: String) -> Option(String) {
  case string.split_once(slug, ":") {
    Ok(#(scope, _value)) -> Some(scope)
    Error(Nil) -> None
  }
}

/// The value of a scoped tag — "todo" for "status:todo"; the slug
/// itself for plain tags.
pub fn value_of(slug: String) -> String {
  case string.split_once(slug, ":") {
    Ok(#(_scope, value)) -> value
    Error(Nil) -> slug
  }
}

/// Scoped-tag exclusivity: at most one tag per scope in a tag set.
/// Errors with the offending scope and its (sorted, unique) tags.
pub fn ensure_no_scope_conflict(
  slugs: List(String),
) -> Result(Nil, #(String, List(String))) {
  slugs
  |> list.filter_map(fn(slug) {
    case scope_of(slug) {
      Some(scope) -> Ok(#(scope, slug))
      None -> Error(Nil)
    }
  })
  |> list.fold(dict.new(), fn(acc, pair) {
    let #(scope, slug) = pair
    dict.upsert(acc, scope, fn(existing) {
      case existing {
        Some(tags) -> [slug, ..tags]
        None -> [slug]
      }
    })
  })
  |> dict.to_list
  |> list.find_map(fn(entry) {
    let #(scope, tags) = entry
    case list.unique(tags) {
      [_] | [] -> Error(Nil)
      several -> Ok(#(scope, list.sort(several, string.compare)))
    }
  })
  |> fn(found) {
    case found {
      Ok(conflict) -> Error(conflict)
      Error(Nil) -> Ok(Nil)
    }
  }
}

/// Which requested slugs are missing from the live set? Mirrors
/// Tags.ensure_all_exist's decision half (the query stays a cap).
pub fn unknown_tags(
  requested: List(String),
  existing: List(String),
) -> Result(Nil, List(String)) {
  case
    requested
    |> list.unique
    |> list.filter(fn(slug) { !list.contains(existing, slug) })
  {
    [] -> Ok(Nil)
    missing -> Error(missing)
  }
}
