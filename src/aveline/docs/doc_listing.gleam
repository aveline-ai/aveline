//// GET /docs list/search parameters — parsing and author resolution,
//// pure. The heavy SQL stays behind the coarse `list_docs` cap; these
//// rules decide what reaches it.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Results are capped so an unbounded corpus can't blow out an agent's
/// context window; explicit ?limit goes up to `max_limit`.
pub const default_limit = 25

pub const max_limit = 100

pub type Sort {
  Recent
  Kudos
  Views
  Relevance
}

/// A query param that may arrive absent, as one comma-separated string,
/// or as a repeated list (marshalled by the controller).
pub type RawParam {
  NoValue
  OneValue(String)
  ManyValues(List(String))
}

/// Filters handed to the coarse `list_docs` cap.
pub type DocQuery {
  DocQuery(
    workspace_id: String,
    viewer: String,
    tags: List(String),
    updated: Option(String),
    search: String,
    sort: Sort,
    owner_ids: List(String),
    limit: Int,
    offset: Int,
  )
}

/// `None` sort → caller picks the default (relevance with a query,
/// recency without).
pub fn parse_sort(raw: Option(String)) -> Result(Option(Sort), String) {
  case raw {
    None | Some("") -> Ok(None)
    Some("recent") -> Ok(Some(Recent))
    Some("kudos") -> Ok(Some(Kudos))
    Some("views") -> Ok(Some(Views))
    Some("relevance") -> Ok(Some(Relevance))
    Some(other) ->
      Error(
        "sort must be recent | kudos | views | relevance, got: "
        <> string.inspect(other),
      )
  }
}

pub fn parse_limit(raw: Option(String)) -> Result(Int, String) {
  case raw {
    None | Some("") -> Ok(default_limit)
    Some(s) ->
      case int.parse(s) {
        Ok(n) if 1 <= n && n <= max_limit -> Ok(n)
        _ ->
          Error(
            "limit must be an integer between 1 and "
            <> int.to_string(max_limit),
          )
      }
  }
}

pub fn parse_offset(raw: Option(String)) -> Result(Int, String) {
  case raw {
    None | Some("") -> Ok(0)
    Some(s) ->
      case int.parse(s) {
        Ok(n) if n >= 0 -> Ok(n)
        _ -> Error("offset must be a non-negative integer")
      }
  }
}

/// Tag/author list params: a string splits on commas (empty pieces
/// dropped), a list passes through; both de-duplicated, order kept.
pub fn parse_list_param(raw: RawParam) -> List(String) {
  case raw {
    NoValue -> []
    ManyValues(values) -> list.unique(values)
    OneValue(s) ->
      s
      |> string.split(",")
      |> list.filter(fn(piece) { piece != "" })
      |> list.unique
  }
}

/// Map author usernames onto member user ids (order kept). Any username
/// not in `members` fails the whole request, listing the unknowns.
pub fn resolve_usernames(
  usernames: List(String),
  members: List(#(String, String)),
) -> Result(List(String), List(String)) {
  let unknown =
    list.filter(usernames, fn(username) {
      !list.any(members, fn(member) { member.0 == username })
    })

  case unknown {
    [] ->
      Ok(
        list.map(usernames, fn(username) {
          let assert Ok(#(_, id)) =
            list.find(members, fn(member) { member.0 == username })
          id
        }),
      )
    _ -> Error(unknown)
  }
}
