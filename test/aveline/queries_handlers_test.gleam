//// Handler tests for the six /queries actions — every branch, IO
//// stubbed. Untouched caps panic, so each test also proves which IO
//// the branch performs.

import aveline/caps/queries.{QueriesCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/fakes
import aveline/handlers/queries as handlers
import aveline/queries/query.{
  Derived, NewQuery, Query, Raw, SourceRef, VersionAttrs,
}
import aveline/queries_fixtures as fixtures
import gleam/option.{None, Some}

fn with_caps(caps: queries.QueriesCaps) -> ctx.Ctx {
  Ctx(..fakes.ctx(), queries: caps)
}

// ── index ──────────────────────────────────────────────────────────

pub fn index_without_source_lists_workspace_test() {
  let q = fixtures.raw_query(name: "signups")
  let ctx =
    with_caps(
      QueriesCaps(..queries.stub(), list_for_workspace: fn(ws) {
        assert ws == "ws-1"
        [q]
      }),
    )

  assert handlers.index(ctx, fakes.scope(), None) == Ok([q])
}

pub fn index_with_unknown_source_lists_nothing_test() {
  let ctx =
    with_caps(
      QueriesCaps(..queries.stub(), get_source_by_name: fn(_, _) { None }),
    )

  assert handlers.index(ctx, fakes.scope(), Some("ghost")) == Ok([])
}

pub fn index_with_source_lists_its_lineage_test() {
  let q = fixtures.raw_query(name: "signups")
  let ctx =
    with_caps(
      QueriesCaps(
        ..queries.stub(),
        get_source_by_name: fn(_, name) {
          assert name == "self"
          Some(SourceRef("src-base-1", False))
        },
        list_for_source: fn(ws, base_id) {
          assert ws == "ws-1"
          assert base_id == "src-base-1"
          [q]
        },
      ),
    )

  assert handlers.index(ctx, fakes.scope(), Some("self")) == Ok([q])
}

// ── show ───────────────────────────────────────────────────────────

pub fn show_missing_is_not_found_test() {
  let ctx = with_caps(fixtures.returning(None))

  assert handlers.show(ctx, fakes.scope(), "nope") == Error(NotFound)
}

pub fn show_returns_the_query_test() {
  let q = fixtures.raw_query(name: "signups")
  let ctx = with_caps(fixtures.returning(Some(q)))

  assert handlers.show(ctx, fakes.scope(), "signups") == Ok(q)
}

// ── create (raw) ───────────────────────────────────────────────────

pub fn create_raw_with_unknown_source_test() {
  let ctx =
    with_caps(
      QueriesCaps(..queries.stub(), get_source_by_name: fn(_, _) { None }),
    )

  assert handlers.create(ctx, fakes.scope(), create_request("x", Some("ghost")))
    == Error(Invalid("data_source_not_found", "no data source named \"ghost\""))
}

pub fn create_raw_over_workspace_source_is_rejected_test() {
  let ctx =
    with_caps(
      QueriesCaps(..queries.stub(), get_source_by_name: fn(_, _) {
        Some(SourceRef("src-base-w", True))
      }),
    )

  assert handlers.create(
      ctx,
      fakes.scope(),
      create_request("x", Some("derived")),
    )
    == Error(Invalid(
      "invalid_query",
      "raw queries target external sources; a query over the workspace catalog is a derived query (omit source)",
    ))
}

pub fn create_raw_normalizes_and_inserts_test() {
  let inserted = fixtures.raw_query(name: "signups")
  let ctx =
    with_caps(
      QueriesCaps(
        ..queries.stub(),
        get_source_by_name: fn(_, _) { Some(SourceRef("src-base-1", False)) },
        insert: fn(ws, attrs) {
          assert ws == "ws-1"
          assert attrs
            == NewQuery(
              name: "signups",
              description: Some("Daily signups."),
              kind: Raw,
              data_source_id: Some("src-base-1"),
              sql: "select 1 as n",
              created_by_id: "user-1",
            )
          Ok(inserted)
        },
      ),
    )

  let request =
    handlers.CreateRequest(
      name: "  Signups ",
      sql: "select 1 as n",
      description: Some("  Daily signups. "),
      source: Some("self"),
    )

  assert handlers.create(ctx, fakes.scope(), request) == Ok(inserted)
}

pub fn create_raw_with_bad_name_is_rejected_before_insert_test() {
  // insert stays a stub: reaching it would panic.
  let ctx =
    with_caps(
      QueriesCaps(..queries.stub(), get_source_by_name: fn(_, _) {
        Some(SourceRef("src-base-1", False))
      }),
    )

  assert handlers.create(
      ctx,
      fakes.scope(),
      create_request("Has Spaces", Some("self")),
    )
    == Error(Invalid(
      "invalid_query",
      "name must be a table-safe identifier: lowercase letter first, then lowercase letters, digits, underscores (40 chars max)",
    ))
}

// ── create (derived) ───────────────────────────────────────────────

pub fn create_derived_with_unparseable_sql_test() {
  let ctx =
    with_caps(
      QueriesCaps(..fixtures.caps(), parse: fn(_) {
        Error("exactly one SELECT statement, please (got 0)")
      }),
    )

  assert handlers.create(ctx, fakes.scope(), create_request("bad", None))
    == Error(Invalid(
      "invalid_query",
      "exactly one SELECT statement, please (got 0)",
    ))
}

pub fn create_derived_with_unknown_reference_test() {
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.catalog(
          live: [fixtures.raw_query(name: "base_a")],
          edges: [],
        ),
        parse: fn(_) { Ok(["nonexistent"]) },
      ),
    )

  assert handlers.create(ctx, fakes.scope(), create_request("bad", None))
    == Error(Invalid(
      "invalid_query",
      "unknown catalog query: nonexistent — every referenced table must be a catalog query in this workspace (aveline list-queries)",
    ))
}

pub fn create_derived_self_reference_is_a_cycle_test() {
  let ctx =
    with_caps(
      QueriesCaps(..fixtures.catalog(live: [], edges: []), parse: fn(_) {
        Ok(["selfy"])
      }),
    )

  assert handlers.create(ctx, fakes.scope(), create_request("selfy", None))
    == Error(Invalid(
      "invalid_query",
      "circular reference involving: selfy — the catalog must stay a DAG",
    ))
}

pub fn create_derived_blank_name_and_sql_report_together_test() {
  let ctx =
    with_caps(
      QueriesCaps(..fixtures.catalog(live: [], edges: []), parse: fn(sql) {
        assert sql == ""
        Ok([])
      }),
    )

  let request =
    handlers.CreateRequest(name: "  ", sql: "", description: None, source: None)

  assert handlers.create(ctx, fakes.scope(), request)
    == Error(Invalid("invalid_query", "name can't be blank; sql can't be blank"))
}

pub fn create_derived_inserts_under_the_graph_lock_test() {
  let base = fixtures.raw_query(name: "base_a")
  let inserted =
    fixtures.derived_query(name: "joined", sql: "select v FROM base_a")
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.catalog(live: [base], edges: []),
        with_graph_lock: fn(ws, thunk) {
          assert ws == "ws-1"
          thunk()
        },
        parse: fn(_) { Ok(["base_a"]) },
        insert: fn(_, attrs) {
          assert attrs
            == NewQuery(
              name: "joined",
              description: None,
              kind: Derived,
              data_source_id: None,
              sql: "select v FROM base_a",
              created_by_id: "user-1",
            )
          Ok(inserted)
        },
      ),
    )

  let request =
    handlers.CreateRequest(
      name: "joined",
      sql: "select v FROM base_a",
      description: None,
      source: None,
    )

  assert handlers.create(ctx, fakes.scope(), request) == Ok(inserted)
}

pub fn create_derived_taken_name_maps_the_constraint_message_test() {
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.catalog(live: [], edges: []),
        parse: fn(_) { Ok([]) },
        insert: fn(_, _) { Error("name already exists") },
      ),
    )

  assert handlers.create(ctx, fakes.scope(), create_request("taken", None))
    == Error(Invalid("invalid_query", "name already exists"))
}

// ── update ─────────────────────────────────────────────────────────

pub fn update_missing_is_not_found_test() {
  let ctx = with_caps(fixtures.returning(None))

  assert handlers.update(ctx, fakes.scope(), "nope", edit_request())
    == Error(NotFound)
}

pub fn update_rename_with_dependents_is_rejected_test() {
  let leaf = fixtures.derived_query(name: "leaf", sql: "select k FROM base_a")
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.returning(Some(leaf)),
        with_graph_lock: fn(_, thunk) { thunk() },
        derived_edges: fn(_) { [#("onleaf", ["leaf"])] },
      ),
    )

  let request =
    handlers.EditRequest(
      new_name: Some("renamed"),
      sql: None,
      description: None,
    )

  assert handlers.update(ctx, fakes.scope(), "leaf", request)
    == Error(Invalid(
      "query_has_dependents",
      "cannot rename \"leaf\": derived query onleaf references it — update it first",
    ))
}

pub fn update_derived_sql_closing_a_cycle_is_rejected_test() {
  let lvl1 = fixtures.derived_query(name: "lvl1", sql: "select k FROM base_a")
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.returning(Some(lvl1)),
        with_graph_lock: fn(_, thunk) { thunk() },
        parse: fn(_) { Ok(["lvl2"]) },
        list_for_workspace: fn(_) {
          [
            lvl1,
            fixtures.derived_query(name: "lvl2", sql: "select k FROM lvl1"),
          ]
        },
        derived_edges: fn(_) { [#("lvl1", ["base_a"]), #("lvl2", ["lvl1"])] },
      ),
    )

  let request =
    handlers.EditRequest(
      new_name: None,
      sql: Some("select k FROM lvl2"),
      description: None,
    )

  assert handlers.update(ctx, fakes.scope(), "lvl1", request)
    == Error(Invalid(
      "invalid_query",
      "circular reference involving: lvl1, lvl2 — the catalog must stay a DAG",
    ))
}

pub fn update_derived_reference_to_own_old_name_after_rename_test() {
  // Renaming "old" to "new" while its SQL still reads "old" fails:
  // the old name is swapped out of the known set.
  let old = fixtures.derived_query(name: "old", sql: "select k FROM base_a")
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.returning(Some(old)),
        with_graph_lock: fn(_, thunk) { thunk() },
        parse: fn(_) { Ok(["old"]) },
        list_for_workspace: fn(_) { [old] },
        derived_edges: fn(_) { [#("old", ["base_a"])] },
      ),
    )

  let request =
    handlers.EditRequest(
      new_name: Some("new"),
      sql: Some("select k FROM old"),
      description: None,
    )

  assert handlers.update(ctx, fakes.scope(), "old", request)
    == Error(Invalid(
      "invalid_query",
      "unknown catalog query: old — every referenced table must be a catalog query in this workspace (aveline list-queries)",
    ))
}

pub fn update_raw_skips_parsing_and_versions_test() {
  // parse stays a stub: raw edits must not call it.
  let current =
    Query(..fixtures.raw_query(name: "signups"), description: Some("Old."))
  let next = Query(..current, id: "q-v2", version_number: 2)
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.returning(Some(current)),
        with_graph_lock: fn(_, thunk) { thunk() },
        insert_next_version: fn(ws, got_current, attrs, user_id) {
          assert ws == "ws-1"
          assert got_current == current
          assert attrs
            == VersionAttrs(
              name: "signups",
              description: Some("Old."),
              sql: "select 2 as n",
            )
          assert user_id == "user-1"
          Ok(next)
        },
      ),
    )

  let request =
    handlers.EditRequest(
      new_name: None,
      sql: Some("select 2 as n"),
      description: None,
    )

  assert handlers.update(ctx, fakes.scope(), "signups", request) == Ok(next)
}

pub fn update_explicit_null_description_clears_it_test() {
  let current =
    Query(..fixtures.raw_query(name: "signups"), description: Some("Old."))
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.returning(Some(current)),
        with_graph_lock: fn(_, thunk) { thunk() },
        insert_next_version: fn(_, _, attrs, _) {
          assert attrs
            == VersionAttrs(
              name: "signups",
              description: None,
              sql: "select 1 as n",
            )
          Ok(current)
        },
      ),
    )

  let request =
    handlers.EditRequest(new_name: None, sql: None, description: Some(None))

  assert handlers.update(ctx, fakes.scope(), "signups", request) == Ok(current)
}

pub fn update_name_conflict_maps_the_constraint_message_test() {
  let current = fixtures.raw_query(name: "signups")
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.returning(Some(current)),
        with_graph_lock: fn(_, thunk) { thunk() },
        derived_edges: fn(_) { [] },
        insert_next_version: fn(_, _, _, _) { Error("name already exists") },
      ),
    )

  let request =
    handlers.EditRequest(new_name: Some("taken"), sql: None, description: None)

  assert handlers.update(ctx, fakes.scope(), "signups", request)
    == Error(Invalid("invalid_query", "name already exists"))
}

// ── delete ─────────────────────────────────────────────────────────

pub fn delete_missing_is_not_found_test() {
  let ctx = with_caps(fixtures.returning(None))

  assert handlers.delete(ctx, fakes.scope(), "nope") == Error(NotFound)
}

pub fn delete_with_dependents_is_rejected_test() {
  let leaf = fixtures.raw_query(name: "leaf")
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.returning(Some(leaf)),
        with_graph_lock: fn(_, thunk) { thunk() },
        derived_edges: fn(_) { [#("zeta", ["leaf"]), #("alpha", ["leaf"])] },
      ),
    )

  assert handlers.delete(ctx, fakes.scope(), "leaf")
    == Error(Invalid(
      "query_has_dependents",
      "cannot delete \"leaf\": derived queries alpha, zeta reference it — update them first",
    ))
}

pub fn delete_soft_deletes_under_the_lock_test() {
  let q = fixtures.raw_query(name: "signups")
  let ctx =
    with_caps(
      QueriesCaps(
        ..fixtures.returning(Some(q)),
        with_graph_lock: fn(_, thunk) { thunk() },
        derived_edges: fn(_) { [] },
        soft_delete: fn(id, user_id) {
          assert id == "q-signups"
          assert user_id == "user-1"
          Query(..q, deleted: True)
        },
      ),
    )

  assert handlers.delete(ctx, fakes.scope(), "signups") == Ok(Nil)
}

// ── restore ────────────────────────────────────────────────────────

pub fn restore_missing_is_not_found_test() {
  let ctx =
    with_caps(
      QueriesCaps(..queries.stub(), get_latest_deleted_by_name: fn(_, _) {
        None
      }),
    )

  assert handlers.restore(ctx, fakes.scope(), "nope") == Error(NotFound)
}

pub fn restore_undeletes_test() {
  let deleted = Query(..fixtures.raw_query(name: "signups"), deleted: True)
  let restored = Query(..deleted, deleted: False)
  let ctx =
    with_caps(
      QueriesCaps(
        ..queries.stub(),
        get_latest_deleted_by_name: fn(ws, name) {
          assert ws == "ws-1"
          assert name == "signups"
          Some(deleted)
        },
        restore: fn(id) {
          assert id == "q-signups"
          Ok(restored)
        },
      ),
    )

  assert handlers.restore(ctx, fakes.scope(), "signups") == Ok(restored)
}

pub fn restore_onto_a_retaken_name_fails_test() {
  let deleted = Query(..fixtures.raw_query(name: "signups"), deleted: True)
  let ctx =
    with_caps(
      QueriesCaps(
        ..queries.stub(),
        get_latest_deleted_by_name: fn(_, _) { Some(deleted) },
        restore: fn(_) { Error("name already exists") },
      ),
    )

  assert handlers.restore(ctx, fakes.scope(), "signups")
    == Error(Invalid("invalid_query", "name already exists"))
}

// ── helpers ────────────────────────────────────────────────────────

fn create_request(
  name: String,
  source: option.Option(String),
) -> handlers.CreateRequest {
  handlers.CreateRequest(
    name: name,
    sql: "select 1",
    description: None,
    source: source,
  )
}

fn edit_request() -> handlers.EditRequest {
  handlers.EditRequest(new_name: None, sql: None, description: None)
}
