# shellcheck shell=bash
# Data sources + catalog queries + chart blocks — connect a database
# (the e2e DB itself), name a query on it, chart it from a doc, and
# verify: the password never leaks, the template renders verbatim,
# edits follow the template-requires-password rule, and failures are
# block states. Charts are named-only: a chart block references a
# catalog query (query_ref); the query owns the SQL and the source.
# Write-protection is the connection user's grants, not ours —
# deliberately untested here.

e2e_db_template() {
  echo "postgres://${PGUSER:-postgres}:<password>@${PGHOST:-localhost}/${E2E_DB_NAME:-aveline_e2e}"
}

e2e_db_password() { echo "${PGPASSWORD:-postgres}"; }

mk_source() { # ws, name
  run_cli -w "$1" create-data-source --name "$2" \
    --url "$(e2e_db_template)" --password "$(e2e_db_password)"
}

mk_query() { # ws, name, source, sql
  run_cli -w "$1" create-query --name "$2" --source "$3" --sql "$4"
}

block_chart() { # query_ref, viz-json
  jq -nc --arg ref "$1" --argjson viz "$2" \
    '{type: "chart", query_ref: $ref, viz: $viz}'
}

# External sources only — the built-in workspace catalog row (built_in)
# is always present in list-data-sources.
EXTERNAL_SOURCES='.data_sources | map(select(.built_in != true))'

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
  expect_eq "$EXTERNAL_SOURCES | length" "1" "one external source"
  expect_eq '.data_sources | map(select(.built_in == true)) | length' "1" "built-in catalog source present"
  expect_absent '.data_sources[0].password' "no password field in the payload"
  expect_absent '.data_sources[1].password' "no password field on the second row either"
  if jq -e "$EXTERNAL_SOURCES | .[0].url | test(\"<password>\")" <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
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
  mk_query "$ws" numbers selfdb "select generate_series(1, 3) as n"
  expect_ok "create-query ok"

  run_cli -w "$ws" create-doc --title "Dash $(us d)" \
    --blocks "[$(block_chart numbers '{"type": "table"}')]"
  expect_ok "create doc with chart block"
  local dash; dash="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$dash"
  expect_ok "get-doc ok"
  expect_eq '.doc.blocks[0].source.name' "selfdb" "source echoed by name"
  if jq -e '.doc.blocks[0].query_sql | test("generate_series")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "query SQL echoed on the block"
  else
    fail "expected query_sql echo on the chart block"
  fi
  if jq -e '.doc.blocks[0].source.url | test("<password>")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "source echo carries the template, placeholder intact"
  else
    fail "source echo should carry the masked template"
  fi

  # get-doc returns config only; rows come from run-block on demand.
  local block_id; block_id="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" run-block "$dash" "$block_id"
  expect_ok "run-block ok"
  expect_eq '.columns[0]' "n" "result columns returned"
  expect_eq '.rows | length' "3" "result rows returned"
}

test_chart_unknown_query_rejected() {
  local ws; ws="$(mk_workspace ds-ghost)"
  run_cli -w "$ws" create-doc --title "Bad dash" \
    --blocks "[$(block_chart ghost '{"type": "table"}')]"
  expect_err "query_not_found" 2 "unknown query_ref → query_not_found"
}

test_edit_rules() {
  local ws; ws="$(mk_workspace ds-edit)"
  mk_source "$ws" selfdb
  mk_query "$ws" one selfdb "select 1 as one"

  run_cli -w "$ws" create-doc --title "Dash $(us e)" \
    --blocks "[$(block_chart one '{"type": "table"}')]"
  local dash; dash="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  # Rename alone: fine, charts keep working (queries pin the base id).
  run_cli -w "$ws" edit-data-source selfdb --new-name maindb
  expect_ok "rename ok"
  expect_eq '.data_source.version_number' "2" "rename minted a version"

  run_cli -w "$ws" get-doc "$dash"
  expect_eq '.doc.blocks[0].source.name' "maindb" "echo shows the new name"
  local block_id; block_id="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" run-block "$dash" "$block_id"
  expect_eq '.rows[0][0]' "1" "chart survives rename"

  # Password-only rotation: fine.
  run_cli -w "$ws" edit-data-source maindb --password "$(e2e_db_password)"
  expect_ok "rotation ok"
  expect_eq '.data_source.version_number' "3" "rotation minted a version"

  # Template change without password: refused.
  run_cli -w "$ws" edit-data-source maindb --url "postgres://u:<password>@evil.example.com/db"
  expect_err "password_required" 2 "template change without password refused"
}

test_query_data_source_adhoc() {
  local ws; ws="$(mk_workspace ds-query)"
  mk_source "$ws" selfdb

  run_cli -w "$ws" query-data-source selfdb --query "select generate_series(1, 3) as n"
  expect_ok "ad-hoc query ok"
  expect_eq '.columns[0]' "n" "columns returned"
  expect_eq '.rows | length' "3" "rows returned"

  # Schema exploration — the query-authoring workflow.
  run_cli -w "$ws" query-data-source selfdb \
    --query "select table_name from information_schema.tables where table_schema = 'public' limit 3"
  expect_ok "information_schema readable"

  run_cli -w "$ws" query-data-source ghost --query "select 1"
  expect_err "not_found" 4 "unknown source → not_found"
}

test_data_source_delete_destroys_password() {
  local ws; ws="$(mk_workspace ds-del)"
  mk_source "$ws" selfdb
  mk_query "$ws" one selfdb "select 1 as one"

  run_cli -w "$ws" create-doc --title "Dash $(us r)" \
    --blocks "[$(block_chart one '{"type": "table"}')]"
  local dash; dash="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" delete-data-source selfdb
  expect_ok "delete ok"

  run_cli -w "$ws" get-doc "$dash"
  expect_eq '.doc.blocks[0].source.credential' "redacted" "credential state is redacted"
  if jq -e '.doc.blocks[0].source.url | test("<password>")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "template survives deletion for audit"
  else
    fail "deleted source should still echo its template"
  fi
  local block_id; block_id="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" run-block "$dash" "$block_id"
  expect_err "query_failed" 2 "running against a deleted source is a block-state error"
  if grep -q "deleted" <<<"$LAST_ERR_TEXT$LAST_OUT_TEXT"; then
    pass "error names the deleted-source state"
  else
    fail "expected the deleted-source message"
  fi

  # No restore verb — the name frees up for a replacement instead. The
  # old query still pins the dead source's base id, so recovery is a new
  # query on the replacement + repointing the block's query_ref.
  mk_source "$ws" selfdb
  expect_ok "name reusable after delete"
  mk_query "$ws" one_again selfdb "select 1 as one"
  expect_ok "replacement query ok"

  run_cli -w "$ws" apply-ops "$dash" --intent "repoint chart at replacement query" \
    --ops "$(jq -nc --arg id "$block_id" '[{op: "modify_block", id: $id, patch: {query_ref: "one_again"}}]')"
  expect_ok "repoint ok"

  run_cli -w "$ws" get-doc "$dash"
  block_id="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" run-block "$dash" "$block_id"
  expect_eq '.rows[0][0]' "1" "chart lives on the replacement source"
}
