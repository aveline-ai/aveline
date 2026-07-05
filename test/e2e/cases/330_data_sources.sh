# shellcheck shell=bash
# Data sources + chart blocks — connect a database (the e2e DB itself),
# chart it from a doc, and verify the credential never leaks, writes
# are refused, and failures are block states rather than errors.

e2e_db_url() {
  echo "postgres://${PGUSER:-postgres}:${PGPASSWORD:-postgres}@${PGHOST:-localhost}/${E2E_DB_NAME:-aveline_e2e}"
}

block_chart() { # source, query, viz-json
  jq -nc --arg source "$1" --arg query "$2" --argjson viz "$3" \
    '{type: "chart", source: $source, query: $query, viz: $viz}'
}

test_data_source_create_and_list_never_leak_url() {
  local ws; ws="$(mk_workspace ds-create)"

  run_cli -w "$ws" create-data-source --name selfdb --url "$(e2e_db_url)"
  expect_ok "create-data-source ok"
  expect_eq '.data_source.adapter' "postgres" "adapter derived from scheme"
  expect_absent '.data_source.url' "url not echoed on create"

  run_cli -w "$ws" list-data-sources
  expect_ok "list ok"
  expect_eq '.data_sources | length' "1" "one source"
  expect_eq '.data_sources[0].name' "selfdb" "name listed"
  if jq -e 'tojson | test("secret|postgres://") | not' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "no connection URL anywhere in the list payload"
  else
    fail "list payload leaks a connection URL"
  fi
}

test_data_source_bad_url_rejected() {
  local ws; ws="$(mk_workspace ds-bad)"
  run_cli -w "$ws" create-data-source --name bad --url "http://example.com/db"
  expect_err "invalid_data_source_url" 2 "http scheme → invalid_data_source_url"
}

test_chart_block_runs_query_on_read() {
  local ws; ws="$(mk_workspace ds-chart)"
  run_cli -w "$ws" create-data-source --name selfdb --url "$(e2e_db_url)"

  run_cli -w "$ws" create-doc --title "Dash $(us d)" \
    --blocks "[$(block_chart selfdb "select generate_series(1, 3) as n" '{"type": "table"}')]"
  expect_ok "create doc with chart block"
  local dash; dash="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$dash"
  expect_ok "get-doc ok"
  expect_eq '.doc.blocks[0].result.columns[0]' "n" "result columns echoed"
  expect_eq '.doc.blocks[0].result.rows | length' "3" "result rows echoed"
  expect_eq '.doc.blocks[0].source.name' "selfdb" "source echoed by name"
  expect_absent '.doc.blocks[0].source.url' "source echo carries no url"
  expect_absent '.doc.blocks[0].data_source' "no stray fields"
}

test_chart_unknown_source_rejected() {
  local ws; ws="$(mk_workspace ds-ghost)"
  run_cli -w "$ws" create-doc --title "Bad dash" \
    --blocks "[$(block_chart ghost "select 1" '{"type": "table"}')]"
  expect_err "data_source_not_found" 2 "unknown source → data_source_not_found"
}

test_chart_write_query_is_error_state() {
  local ws; ws="$(mk_workspace ds-write)"
  run_cli -w "$ws" create-data-source --name selfdb --url "$(e2e_db_url)"

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

test_data_source_delete_restore_roundtrip() {
  local ws; ws="$(mk_workspace ds-del)"
  run_cli -w "$ws" create-data-source --name selfdb --url "$(e2e_db_url)"

  run_cli -w "$ws" create-doc --title "Dash $(us r)" \
    --blocks "[$(block_chart selfdb "select 1 as one" '{"type": "table"}')]"
  local dash; dash="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" delete-data-source selfdb
  expect_ok "delete ok"

  run_cli -w "$ws" get-doc "$dash"
  if jq -e '.doc.blocks[0].result.error | test("deleted")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "chart shows deleted-source state"
  else
    fail "expected deleted-source error state"
  fi

  run_cli -w "$ws" restore-data-source selfdb
  expect_ok "restore ok"

  run_cli -w "$ws" get-doc "$dash"
  expect_eq '.doc.blocks[0].result.rows[0][0]' "1" "chart lives again after restore"
}
