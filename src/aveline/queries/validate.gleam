//// Pure write-time validation for catalog queries. Ports the
//// Query.insert_changeset rules reachable from the API (name presence
//// and format, sql presence and length) with the exact messages, in
//// the exact order, the Ecto changeset would report them — so error
//// envelopes don't change.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

const name_format_message = "name must be a table-safe identifier: lowercase letter first, then lowercase letters, digits, underscores (40 chars max)"

/// The context normalizes names before validating: trim + downcase.
pub fn normalize_name(raw: String) -> String {
  raw |> string.trim |> string.lowercase
}

/// Descriptions trim to None when blank.
pub fn normalize_description(raw: Option(String)) -> Option(String) {
  case raw {
    None -> None
    Some(d) ->
      case string.trim(d) {
        "" -> None
        trimmed -> Some(trimmed)
      }
  }
}

/// `^[a-z][a-z0-9_]{0,39}$` — names are table identifiers inside
/// agent-written SQL, so the charset is strict.
pub fn valid_name(name: String) -> Bool {
  case string.pop_grapheme(name) {
    Error(Nil) -> False
    Ok(#(first, rest)) ->
      is_lower(first)
      && string.length(rest) <= 39
      && list.all(string.to_graphemes(rest), fn(c) {
        is_lower(c) || is_digit(c) || c == "_"
      })
  }
}

/// Validate a (normalized) name + sql pair as insert_changeset would.
/// Error carries the changeset-style message: "field message" pairs
/// joined with "; ", most recently run validation first.
pub fn validate_insert(name: String, sql: String) -> Result(Nil, String) {
  let required =
    []
    |> append_if(name == "", "name can't be blank")
    |> append_if(sql == "", "sql can't be blank")

  let errors =
    required
    |> prepend_if(name != "" && !valid_name(name), name_format_message)
    |> prepend_if(
      sql != "" && string.length(sql) > 10_000,
      "sql should be at most 10000 character(s)",
    )

  case errors {
    [] -> Ok(Nil)
    messages -> Error(string.join(messages, "; "))
  }
}

fn append_if(
  errors: List(String),
  cond: Bool,
  message: String,
) -> List(String) {
  case cond {
    True -> list.append(errors, [message])
    False -> errors
  }
}

fn prepend_if(
  errors: List(String),
  cond: Bool,
  message: String,
) -> List(String) {
  case cond {
    True -> [message, ..errors]
    False -> errors
  }
}

fn is_lower(c: String) -> Bool {
  string.contains(does: "abcdefghijklmnopqrstuvwxyz", contain: c)
}

fn is_digit(c: String) -> Bool {
  string.contains(does: "0123456789", contain: c)
}
