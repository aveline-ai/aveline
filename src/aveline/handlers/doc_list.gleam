//// GET /docs — list/search current docs. Ports DocController.index:
//// param parsing (sort/limit/offset/tags/authors), author resolution,
//// and the default-sort decision; the heavy search SQL stays behind the
//// coarse `list_docs` cap, which returns rendered summaries.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{Invalid}
import aveline/core/scope.{type Scope}
import aveline/docs/doc_error.{type DocError, Api, UnknownAuthors}
import aveline/docs/doc_listing.{type RawParam, DocQuery, Recent, Relevance}
import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub type ListRequest {
  ListRequest(
    sort: Option(String),
    limit: Option(String),
    offset: Option(String),
    tags: RawParam,
    authors: RawParam,
    edited: Option(String),
    updated: Option(String),
    q: Option(String),
  )
}

pub fn index(
  ctx: Ctx,
  scope: Scope,
  req: ListRequest,
) -> Result(Dynamic, DocError) {
  use sort_param <- result.try(list_param(doc_listing.parse_sort(req.sort)))
  use limit <- result.try(list_param(doc_listing.parse_limit(req.limit)))
  use offset <- result.try(list_param(doc_listing.parse_offset(req.offset)))
  use owner_ids <- result.try(resolve_authors(
    ctx,
    scope,
    doc_listing.parse_list_param(req.authors),
  ))

  let search = string.trim(option.unwrap(req.q, ""))
  // No explicit sort + a search query → relevance; recency otherwise.
  let sort =
    option.unwrap(sort_param, case search {
      "" -> Recent
      _ -> Relevance
    })

  Ok(
    ctx.docs.list_docs(DocQuery(
      workspace_id: scope.workspace.id,
      viewer: scope.actor.id,
      tags: doc_listing.parse_list_param(req.tags),
      updated: option.or(req.edited, req.updated),
      search: search,
      sort: sort,
      owner_ids: owner_ids,
      limit: limit,
      offset: offset,
    )),
  )
}

fn list_param(parsed: Result(a, String)) -> Result(a, DocError) {
  result.map_error(parsed, fn(message) {
    Api(Invalid("list_param_invalid", message))
  })
}

fn resolve_authors(
  ctx: Ctx,
  scope: Scope,
  usernames: List(String),
) -> Result(List(String), DocError) {
  case usernames {
    [] -> Ok([])
    _ ->
      case
        doc_listing.resolve_usernames(
          usernames,
          ctx.docs.member_usernames(scope.workspace.id),
        )
      {
        Ok(ids) -> Ok(ids)
        Error(unknown) -> Error(UnknownAuthors(unknown))
      }
  }
}
