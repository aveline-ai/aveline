//// Pure rules: name/sql validation (changeset parity) and the graph
//// checks (references, cycles, depth, dependents).

import aveline/queries/rules
import aveline/queries/validate
import gleam/option.{None, Some}
import gleam/string

const name_format_message = "name must be a table-safe identifier: lowercase letter first, then lowercase letters, digits, underscores (40 chars max)"

// ── names ──────────────────────────────────────────────────────────

pub fn valid_names_test() {
  assert validate.valid_name("a")
  assert validate.valid_name("signups_2026")
  assert validate.valid_name("a" <> string.repeat("b", 39))
}

pub fn invalid_names_test() {
  assert !validate.valid_name("")
  assert !validate.valid_name("1a")
  assert !validate.valid_name("_a")
  assert !validate.valid_name("A")
  assert !validate.valid_name("has spaces")
  assert !validate.valid_name("has-dash")
  assert !validate.valid_name("a" <> string.repeat("b", 40))
}

pub fn normalize_name_trims_and_downcases_test() {
  assert validate.normalize_name("  Signups ") == "signups"
}

pub fn normalize_description_test() {
  assert validate.normalize_description(None) == None
  assert validate.normalize_description(Some("   ")) == None
  assert validate.normalize_description(Some(" hi ")) == Some("hi")
}

// ── validate_insert (changeset-parity messages) ────────────────────

pub fn validate_insert_ok_test() {
  assert validate.validate_insert("signups", "select 1") == Ok(Nil)
}

pub fn blank_name_and_sql_report_in_required_order_test() {
  assert validate.validate_insert("", "")
    == Error("name can't be blank; sql can't be blank")
}

pub fn bad_format_reports_before_blank_sql_test() {
  assert validate.validate_insert("has spaces", "")
    == Error(name_format_message <> "; sql can't be blank")
}

pub fn long_sql_reports_before_bad_name_test() {
  assert validate.validate_insert("has spaces", string.repeat("a", 10_001))
    == Error(
      "sql should be at most 10000 character(s); " <> name_format_message,
    )
}

pub fn sql_at_cap_is_fine_test() {
  assert validate.validate_insert("ok", string.repeat("a", 10_000)) == Ok(Nil)
}

// ── refs_resolve ───────────────────────────────────────────────────

pub fn refs_resolve_ok_including_own_name_test() {
  assert rules.refs_resolve(["base_a"], ["base_a", "joined"], "joined", None)
    == Ok(Nil)
}

pub fn refs_resolve_unknown_singular_test() {
  assert rules.refs_resolve(["base_a"], ["ghost"], "bad", None)
    == Error(
      "unknown catalog query: ghost — every referenced table must be a catalog query in this workspace (aveline list-queries)",
    )
}

pub fn refs_resolve_unknown_plural_test() {
  assert rules.refs_resolve([], ["ghost", "phantom"], "bad", None)
    == Error(
      "unknown catalog queries: ghost, phantom — every referenced table must be a catalog query in this workspace (aveline list-queries)",
    )
}

pub fn refs_resolve_except_drops_old_name_test() {
  // Editing "old" to be "new": references to "old" no longer resolve.
  assert rules.refs_resolve(["old", "base"], ["old"], "new", Some("old"))
    == Error(
      "unknown catalog query: old — every referenced table must be a catalog query in this workspace (aveline list-queries)",
    )
}

// ── stays_dag ──────────────────────────────────────────────────────

pub fn chain_is_allowed_test() {
  assert rules.stays_dag([#("lvl1", ["base_a"])], None, "lvl2", ["lvl1"])
    == Ok(Nil)
}

pub fn cycle_is_rejected_test() {
  // Editing lvl1 to read lvl2 closes lvl1 -> lvl2 -> lvl1.
  assert rules.stays_dag(
      [#("lvl1", ["base_a"]), #("lvl2", ["lvl1"])],
      Some("lvl1"),
      "lvl1",
      ["lvl2"],
    )
    == Error(
      "circular reference involving: lvl1, lvl2 — the catalog must stay a DAG",
    )
}

pub fn self_reference_is_a_cycle_test() {
  assert rules.stays_dag([], None, "selfy", ["selfy"])
    == Error(
      "circular reference involving: selfy — the catalog must stay a DAG",
    )
}

pub fn depth_cap_is_enforced_test() {
  let edges = [
    #("q01", ["q02"]),
    #("q02", ["q03"]),
    #("q03", ["q04"]),
    #("q04", ["q05"]),
    #("q05", ["q06"]),
    #("q06", ["q07"]),
    #("q07", ["q08"]),
    #("q08", ["q09"]),
  ]

  // Ten levels (q00 through the q09 leaf) is fine…
  assert rules.stays_dag(edges, None, "q00", ["q01"]) == Ok(Nil)

  // …but the eleventh is past the cap.
  let deeper = [#("q09", ["q10"]), ..edges]
  assert rules.stays_dag(deeper, None, "q00", ["q01"])
    == Error("query chains deeper than 10 are not allowed (got 11)")
}

// ── no_derived_dependents ──────────────────────────────────────────

pub fn no_dependents_is_ok_test() {
  assert rules.no_derived_dependents([#("other", ["base_b"])], "leaf", "delete")
    == Ok(Nil)
}

pub fn self_reference_is_not_a_dependent_test() {
  assert rules.no_derived_dependents([#("leaf", ["leaf"])], "leaf", "delete")
    == Ok(Nil)
}

pub fn single_dependent_message_test() {
  assert rules.no_derived_dependents([#("onleaf", ["leaf"])], "leaf", "rename")
    == Error(
      "cannot rename \"leaf\": derived query onleaf references it — update it first",
    )
}

pub fn plural_dependents_are_sorted_test() {
  assert rules.no_derived_dependents(
      [#("zeta", ["leaf"]), #("alpha", ["leaf"])],
      "leaf",
      "delete",
    )
    == Error(
      "cannot delete \"leaf\": derived queries alpha, zeta reference it — update them first",
    )
}
