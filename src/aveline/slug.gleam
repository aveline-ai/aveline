//// Slug rules — pure port of Aveline.Slug. Format `[a-z0-9][a-z0-9-]*`,
//// length 1–60. Used by workspace creation (slug) and data source names.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const max_length = 60

const alnum = "abcdefghijklmnopqrstuvwxyz0123456789"

fn is_alnum(grapheme: String) -> Bool {
  string.contains(does: alnum, contain: grapheme)
}

/// Derive a slug from arbitrary text: lowercase, replace runs of
/// `[^a-z0-9]+` with `-`, trim `-`, cap at 60, trim again. None if
/// nothing remains.
pub fn derive_from(text: String) -> Option(String) {
  let derived =
    text
    |> string.lowercase
    |> string.to_graphemes
    |> list.map(fn(g) {
      case is_alnum(g) {
        True -> g
        False -> "-"
      }
    })
    |> collapse_dashes("")
    |> trim_dashes
    |> string.slice(0, max_length)
    |> trim_dashes

  case derived {
    "" -> None
    _ -> Some(derived)
  }
}

fn collapse_dashes(graphemes: List(String), acc: String) -> String {
  case graphemes {
    [] -> acc
    ["-", ..rest] ->
      case string.ends_with(acc, "-") {
        True -> collapse_dashes(rest, acc)
        False -> collapse_dashes(rest, acc <> "-")
      }
    [g, ..rest] -> collapse_dashes(rest, acc <> g)
  }
}

fn trim_dashes(text: String) -> String {
  case text {
    "-" <> rest -> trim_dashes(rest)
    _ ->
      case string.ends_with(text, "-") {
        True -> trim_dashes(string.drop_end(text, 1))
        False -> text
      }
  }
}

/// Validate slug format (already-lowercased input expected, as in
/// Aveline.Slug.validate/1).
pub fn validate(slug: String) -> Bool {
  case string.to_graphemes(slug) {
    [] -> False
    [first, ..rest] ->
      string.length(slug) <= max_length
      && is_alnum(first)
      && list.all(rest, fn(g) { is_alnum(g) || g == "-" })
  }
}
