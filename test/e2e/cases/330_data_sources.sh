# shellcheck shell=bash
# Data sources + chart blocks — connect a database (the e2e DB itself),
# chart it from a doc, and verify: the password never leaks, the
# template renders verbatim, writes are refused, edits follow the
# template-requires-password rule, and failures are block states.

e2e_db_template() {
  echo "postgres://${PGUSER:-postgres}:<password>@${PGHOST:-localhost}/${E2E_DB_NAME:-aveline_e2e}"
}

e2e_db_password() { echo "${PGPASSWORD:-postgres}"; }

mk_source() { # ws, name
  run_cli -w "$1" create-data-source --name "$2" \
    --url "$(e2e_db_template)" --password "$(e2e_db_password)"
}

block_chart() { # source, query, viz-json
  jq -nc --arg source "$1" --arg query "$2" --argjson viz "$3" \
    '{type: "chart", source: $source, query: $query, viz: $viz}'
}

test_data_source_create_and_list_never_leak_password() {
  local ws; ws="$(mk_workspace ds-create)"

  mk_source "$ws" selfdb
  expect_ok "create-data-source ok"
  expect_eq '.data_source.adapter' "postgres" "adapter derived from scheme"
  expect_eq '.data_source.credential' "live" "credential state echoed"
  if jq -e '.data_source.url | test("<password>")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "template echoed verbatim with placeholder"
  else
    fail "expected the template with <password> in the echo"
  fi

  run_cli -w "$ws" list-data-sources
  expect_ok "list ok"
  expect_eq '.data_sources | length' "1" "one source"
  expect_absent '.data_sources[0].password' "no password field in the payload"
  if jq -e '.data_sources[0].url | test("<password>")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "echoed template still carries the un-substituted placeholder"
  else
    fail "template echo lost its placeholder (possible substitution leak)"
  fi
}

test_data_source_template_needs_placeholder() {
  local ws; ws="$(mk_workspace ds-noplace)"
  run_cli -w "$ws" create-data-source --name bad \
    --url "postgres://u:realpass@h/db" --password "x"
  expect_err "invalid_data_source_url" 2 "template without <password> rejected"
}

test_chart_block_runs_query_on_read() {
  local ws; ws="$(mk_workspace ds-chart)"
  mk_source "$ws" selfdb

  run_cli -w "$ws" create-doc --title "Dash $(us d)" \
    --blocks "[$(block_chart selfdb "select generate_series(1, 3) as n" '{"type": "table"}')]"
  expect_ok "create doc with chart block"
  local dash; dash="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$dash"
  expect_ok "get-doc ok"
  expect_eq '.doc.blocks[0].result.columns[0]' "n" "result columns echoed"
  expect_eq '.doc.blocks[0].result.rows | length' "3" "result rows echoed"
  expect_eq '.doc.blocks[0].source.name' "selfdb" "source echoed by name"
  if jq -e '.doc.blocks[0].source.url | test("<password>")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "source echo carries the template, placeholder intact"
  else
    fail "source echo should carry the masked template"
  fi
}

test_chart_unknown_source_rejected() {
  local ws; ws="$(mk_workspace ds-ghost)"
  run_cli -w "$ws" create-doc --title "Bad dash" \
    --blocks "[$(block_chart ghost "select 1" '{"type": "table"}')]"
  expect_err "data_source_not_found" 2 "unknown source → data_source_not_found"
}

test_chart_write_query_is_error_state() {
  local ws; ws="$(mk_workspace ds-write)"
  mk_source "$ws" selfdb

  run_cli -w "$ws" create-doc --title "Evil dash $(us e)" \
    --blocks "[$(block_chart selfdb "DELETE FROM docs" '{"type": "table"}')]"
  expect_ok "doc with a write query still creates (validity is SQL-agnostic)"
  local dash; dash="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$dash"
  expect_ok "doc still reads"
  if jq -e '.doc.blocks[0].result.error | test("read-only")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "write refused by read-only session, surfaced as block state"
  else
    fail "expected a read-only error state, got: $(jq -c '.doc.blocks[0].result' <<<"$LAST_OUT_TEXT")"
  fi
}

test_edit_rules() {
  local ws; ws="$(mk_workspace ds-edit)"
  mk_source "$ws" selfdb

  run_cli -w "$ws" create-doc --title "Dash $(us e)" \
    --blocks "[$(block_chart selfdb "select 1 as one" '{"type": "table"}')]"
  local dash; dash="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  # Rename alone: fine, charts keep working (blocks pin the base id).
  run_cli -w "$ws" edit-data-source selfdb --new-name maindb
  expect_ok "rename ok"
  expect_eq '.data_source.version_number' "2" "rename minted a version"

  run_cli -w "$ws" get-doc "$dash"
  expect_eq '.doc.blocks[0].result.rows[0][0]' "1" "chart survives rename"
  expect_eq '.doc.blocks[0].source.name' "maindb" "echo shows the new name"

  # Password-only rotation: fine.
  run_cli -w "$ws" edit-data-source maindb --password "$(e2e_db_password)"
  expect_ok "rotation ok"
  expect_eq '.data_source.version_number' "3" "rotation minted a version"

  # Template change without password: refused.
  run_cli -w "$ws" edit-data-source maindb --url "postgres://u:<password>@evil.example.com/db"
  expect_err "password_required" 2 "template change without password refused"
}

test_data_source_delete_destroys_password() {
  local ws; ws="$(mk_workspace ds-del)"
  mk_source "$ws" selfdb

  run_cli -w "$ws" create-doc --title "Dash $(us r)" \
    --blocks "[$(block_chart selfdb "select 1 as one" '{"type": "table"}')]"
  local dash; dash="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" delete-data-source selfdb
  expect_ok "delete ok"

  run_cli -w "$ws" get-doc "$dash"
  if jq -e '.doc.blocks[0].result.error | test("deleted")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "chart shows deleted-source state"
  fi
  expect_eq '.doc.blocks[0].source.credential' "redacted" "credential state is redacted"
  if jq -e '.doc.blocks[0].source.url | test("<password>")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "template survives deletion for audit"
  else
    fail "deleted source should still echo its template"
  fi

  # No restore verb — the name frees up for a replacement instead.
  mk_source "$ws" selfdb
  expect_ok "name reusable after delete"

  run_cli -w "$ws" get-doc "$dash"
  local block_id; block_id="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" apply-ops "$dash" --intent "repoint chart at replacement source" \
    --ops "$(jq -nc --arg id "$block_id" '[{op: "modify_block", id: $id, patch: {source: "selfdb"}}]')"
  expect_ok "repoint ok"

  run_cli -w "$ws" get-doc "$dash"
  expect_eq '.doc.blocks[0].result.rows[0][0]' "1" "chart lives on the replacement source"
}
