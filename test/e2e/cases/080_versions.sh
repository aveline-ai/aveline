# shellcheck shell=bash
# Versions — list, get specific, after apply-ops.

test_list_versions_v1_only() {
  local ws; ws="$(mk_workspace ws-v1)"
  local slug; slug="$(mk_doc "$ws" "Fresh")"
  run_cli -w "$ws" list-versions "$slug"
  expect_ok "list-versions ok"
  expect_count ".versions" "1" "fresh doc has exactly 1 version"
}

test_list_versions_after_apply_ops() {
  local ws; ws="$(mk_workspace ws-v2)"
  local slug; slug="$(mk_doc "$ws" "Bumpable")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'extra')" \
    '{op: "append_block", block: $b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "apply-ops ok"
  run_cli -w "$ws" list-versions "$slug"
  expect_ok "list-versions ok"
  expect_count ".versions" "2" "two versions after one apply-ops"
}

test_get_version_returns_snapshot() {
  local ws; ws="$(mk_workspace ws-vsnap)"
  local slug; slug="$(mk_doc "$ws" "Snap")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'second')" \
    '{op: "append_block", block: $b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "apply-ops to v2 ok"
  run_cli -w "$ws" get-version "$slug" 1
  expect_ok "get-version 1 ok"
  expect_eq ".doc.version_number" "1" "snapshot says v1"
  # mk_doc seeds with 1 block; apply-ops above appends a 2nd.
  expect_count ".doc.blocks" "1" "v1 snapshot has one block"
  run_cli -w "$ws" get-version "$slug" 2
  expect_ok "get-version 2 ok"
  expect_count ".doc.blocks" "2" "v2 snapshot has two blocks"
}

test_get_version_not_found() {
  local ws; ws="$(mk_workspace ws-vnf)"
  local slug; slug="$(mk_doc "$ws" "OneVersion")"
  run_cli -w "$ws" get-version "$slug" 99
  expect_err "not_found" 4 "non-existent version → not_found"
}

test_list_versions_doc_not_found() {
  local ws; ws="$(mk_workspace ws-lvnf)"
  run_cli -w "$ws" list-versions "ghost-$(us)"
  expect_err "not_found" 4 "list-versions on missing doc → not_found"
}
