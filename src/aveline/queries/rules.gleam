//// Pure decision rules for catalog writes — ports the private helpers
//// of Aveline.DataSources.Queries: reference resolution, DAG/depth
//// validation, and dependent protection. All take the graph as data
//// (the handler fetches it through caps) and return the exact legacy
//// error messages.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list.{Continue, Stop}
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string

const depth_cap = 10

/// Every referenced table must be a live catalog name (or the query's
/// own name). `except` drops the pre-rename name during an edit.
pub fn refs_resolve(
  live_names: List(String),
  refs: List(String),
  own_name: String,
  except: Option(String),
) -> Result(Nil, String) {
  let known =
    set.from_list(live_names)
    |> drop_except(except)
    |> set.insert(own_name)

  case list.filter(refs, fn(ref) { !set.contains(known, ref) }) {
    [] -> Ok(Nil)
    unknown ->
      Error(
        "unknown catalog quer"
        <> singular_plural(unknown, "y", "ies")
        <> ": "
        <> string.join(unknown, ", ")
        <> " — every referenced table must be a catalog query in this workspace (aveline list-queries)",
      )
  }
}

/// DFS over the live derived edge set with the candidate edges swapped
/// in: rejects cycles and chains past the depth cap.
pub fn stays_dag(
  derived_edges: List(#(String, List(String))),
  except: Option(String),
  name: String,
  refs: List(String),
) -> Result(Nil, String) {
  let edges =
    derived_edges
    |> list.filter(fn(edge) { Some(edge.0) != except })
    |> dict.from_list
    |> dict.insert(name, refs)

  edges
  |> dict.keys
  |> list.sort(string.compare)
  |> list.fold_until(Ok(Nil), fn(_, start) {
    case depth(start, edges, set.new(), dict.new()) {
      Cycle(involved) ->
        Stop(Error(
          "circular reference involving: "
          <> string.join(list.unique(involved), ", ")
          <> " — the catalog must stay a DAG",
        ))
      Depth(d, _) ->
        case d > depth_cap {
          True ->
            Stop(Error(
              "query chains deeper than "
              <> int.to_string(depth_cap)
              <> " are not allowed (got "
              <> int.to_string(d)
              <> ")",
            ))
          False -> Continue(Ok(Nil))
        }
    }
  })
}

/// Renaming or deleting a query that other derived queries reference
/// is rejected until the dependents are updated.
pub fn no_derived_dependents(
  derived_edges: List(#(String, List(String))),
  name: String,
  action: String,
) -> Result(Nil, String) {
  let dependents =
    derived_edges
    |> list.filter(fn(edge) { edge.0 != name && list.contains(edge.1, name) })
    |> list.map(fn(edge) { edge.0 })
    |> list.sort(string.compare)

  case dependents {
    [] -> Ok(Nil)
    names ->
      Error(
        "cannot "
        <> action
        <> " \""
        <> name
        <> "\": derived quer"
        <> singular_plural(names, "y", "ies")
        <> " "
        <> string.join(names, ", ")
        <> " reference"
        <> singular_plural(names, "s", "")
        <> " it — update "
        <> singular_plural(names, "it", "them")
        <> " first",
      )
  }
}

type DepthResult {
  Cycle(List(String))
  Depth(Int, Dict(String, Int))
}

fn depth(
  node: String,
  edges: Dict(String, List(String)),
  visiting: Set(String),
  memo: Dict(String, Int),
) -> DepthResult {
  case set.contains(visiting, node) {
    True -> Cycle([node, ..set.to_list(visiting) |> list.sort(string.compare)])
    False ->
      case dict.get(memo, node) {
        Ok(d) -> Depth(d, memo)
        Error(Nil) ->
          case dict.get(edges, node) {
            // A leaf (raw query, or a name that isn't a derived query).
            Error(Nil) -> Depth(1, dict.insert(memo, node, 1))
            Ok(refs) -> {
              let visiting = set.insert(visiting, node)

              let folded =
                list.fold_until(refs, Depth(1, memo), fn(acc, ref) {
                  let assert Depth(best, memo) = acc
                  case depth(ref, edges, visiting, memo) {
                    Cycle(involved) -> Stop(Cycle(involved))
                    Depth(d, memo) ->
                      Continue(Depth(int.max(best, d + 1), memo))
                  }
                })

              case folded {
                Cycle(involved) -> Cycle(involved)
                Depth(d, memo) -> Depth(d, dict.insert(memo, node, d))
              }
            }
          }
      }
  }
}

fn drop_except(known: Set(String), except: Option(String)) -> Set(String) {
  case except {
    Some(name) -> set.delete(known, name)
    None -> known
  }
}

fn singular_plural(items: List(a), one: String, many: String) -> String {
  case items {
    [_] -> one
    _ -> many
  }
}
