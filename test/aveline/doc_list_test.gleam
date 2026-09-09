import aveline/caps/docs.{DocsCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid}
import aveline/docs/doc_error.{Api, UnknownAuthors}
import aveline/docs/doc_listing.{
  DocQuery, Kudos, ManyValues, NoValue, OneValue, Recent, Relevance,
}
import aveline/fakes
import aveline/handlers/doc_list.{ListRequest}
import gleam/dynamic
import gleam/option.{None, Some}

fn request() -> doc_list.ListRequest {
  ListRequest(
    sort: None,
    limit: None,
    offset: None,
    tags: NoValue,
    authors: NoValue,
    edited: None,
    updated: None,
    q: None,
  )
}

fn default_query() -> doc_listing.DocQuery {
  DocQuery(
    workspace_id: "ws-1",
    viewer: "user-1",
    tags: [],
    updated: None,
    search: "",
    sort: Recent,
    owner_ids: [],
    limit: 25,
    offset: 0,
  )
}

fn ctx_expecting(expected: doc_listing.DocQuery) -> ctx.Ctx {
  Ctx(
    ..fakes.ctx(),
    docs: DocsCaps(..docs.stub(), list_docs: fn(query) {
      assert query == expected
      dynamic.string("docs")
    }),
  )
}

pub fn defaults_test() {
  assert doc_list.index(
      ctx_expecting(default_query()),
      fakes.scope(),
      request(),
    )
    == Ok(dynamic.string("docs"))
}

pub fn search_defaults_to_relevance_and_trims_test() {
  let expected =
    DocQuery(..default_query(), search: "beam docs", sort: Relevance)
  let req = ListRequest(..request(), q: Some("  beam docs  "))

  assert doc_list.index(ctx_expecting(expected), fakes.scope(), req)
    == Ok(dynamic.string("docs"))
}

pub fn explicit_sort_wins_over_default_test() {
  let expected = DocQuery(..default_query(), search: "beam", sort: Kudos)
  let req = ListRequest(..request(), q: Some("beam"), sort: Some("kudos"))

  assert doc_list.index(ctx_expecting(expected), fakes.scope(), req)
    == Ok(dynamic.string("docs"))
}

pub fn invalid_sort_test() {
  let req = ListRequest(..request(), sort: Some("newest"))

  assert doc_list.index(fakes.ctx(), fakes.scope(), req)
    == Error(
      Api(Invalid(
        "list_param_invalid",
        "sort must be recent | kudos | views | relevance, got: \"newest\"",
      )),
    )
}

pub fn invalid_limit_test() {
  let req = ListRequest(..request(), limit: Some("500"))

  assert doc_list.index(fakes.ctx(), fakes.scope(), req)
    == Error(
      Api(Invalid(
        "list_param_invalid",
        "limit must be an integer between 1 and 100",
      )),
    )
}

pub fn invalid_offset_test() {
  let req = ListRequest(..request(), offset: Some("-3"))

  assert doc_list.index(fakes.ctx(), fakes.scope(), req)
    == Error(
      Api(Invalid("list_param_invalid", "offset must be a non-negative integer")),
    )
}

pub fn tag_string_splits_and_dedupes_test() {
  let expected = DocQuery(..default_query(), tags: ["ops", "runbook"])
  let req = ListRequest(..request(), tags: OneValue("ops,runbook,,ops"))

  assert doc_list.index(ctx_expecting(expected), fakes.scope(), req)
    == Ok(dynamic.string("docs"))
}

pub fn edited_wins_over_updated_test() {
  let expected = DocQuery(..default_query(), updated: Some("7d"))
  let req = ListRequest(..request(), edited: Some("7d"), updated: Some("24h"))

  assert doc_list.index(ctx_expecting(expected), fakes.scope(), req)
    == Ok(dynamic.string("docs"))
}

pub fn authors_resolve_to_owner_ids_test() {
  let expected = DocQuery(..default_query(), owner_ids: ["u2", "u1"])
  let req = ListRequest(..request(), authors: ManyValues(["bo", "arie"]))

  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(
        ..docs.stub(),
        member_usernames: fn(workspace_id) {
          assert workspace_id == "ws-1"
          [#("arie", "u1"), #("bo", "u2")]
        },
        list_docs: fn(query) {
          assert query == expected
          dynamic.string("docs")
        },
      ),
    )

  assert doc_list.index(ctx, fakes.scope(), req) == Ok(dynamic.string("docs"))
}

pub fn unknown_author_is_rejected_test() {
  let req = ListRequest(..request(), authors: OneValue("bo,ghost"))

  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: DocsCaps(..docs.stub(), member_usernames: fn(_) { [#("bo", "u2")] }),
    )

  assert doc_list.index(ctx, fakes.scope(), req)
    == Error(UnknownAuthors(["ghost"]))
}
