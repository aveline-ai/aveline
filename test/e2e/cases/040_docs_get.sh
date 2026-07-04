# shellcheck shell=bash
# get-doc — full block body + error paths.

test_get_doc_returns_full_body() {
  local ws; ws="$(mk_workspace ws-get-doc)"
  mk_tag "$ws" "demo" >/dev/null
  local slug; slug="$(mk_doc "$ws" "Detailed" "demo")"
  run_cli -w "$ws" get-doc "$slug"
  expect_ok "get-doc ok"
  expect_eq ".doc.slug" "$slug" "slug matches"
  expect_present ".doc.title" "title present"
  expect_present ".doc.blocks" "blocks present"
  if jq -e '.doc.blocks | length > 0' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "blocks non-empty"
  else
    fail "blocks empty"
  fi
}

test_get_doc_blocks_have_id_and_type() {
  local ws; ws="$(mk_workspace ws-blockshape)"
  local slug; slug="$(mk_doc "$ws" "Shapes")"
  run_cli -w "$ws" get-doc "$slug"
  expect_ok "get-doc ok"
  if jq -e '.doc.blocks | all(has("id") and has("type"))' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "every block has id + type"
  else
    fail "some block missing id/type"
  fi
}

test_get_doc_returns_version_pointer() {
  local ws; ws="$(mk_workspace ws-vptr)"
  local slug; slug="$(mk_doc "$ws" "V1")"
  run_cli -w "$ws" get-doc "$slug"
  expect_ok "get-doc ok"
  expect_eq ".doc.version_number" "1" "freshly created doc is version 1"
  # .doc.id is this version's row id; .doc.base_doc_id is the logical
  # (cross-version) doc id. Both should be present.
  expect_present ".doc.id" "version row id present"
  expect_present ".doc.base_doc_id" "base doc id present"
}

test_get_doc_includes_tags() {
  local ws; ws="$(mk_workspace ws-meta)"
  mk_tag "$ws" "meta" >/dev/null
  local blocks; blocks="[$(block_paragraph 'm')]"
  run_cli -w "$ws" create-doc --title "Meta" --tag meta --blocks "$blocks"
  expect_ok "doc created"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_ok "get-doc ok"
  if jq -e '.doc.tags | index("meta")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "tags echoed back"
  else
    fail "tags missing"
  fi
}

test_get_doc_not_found() {
  local ws; ws="$(mk_workspace ws-getnf)"
  run_cli -w "$ws" get-doc "ghost-$(us)"
  expect_err "not_found" 4 "missing slug → not_found"
}

test_get_doc_unknown_workspace() {
  run_cli -w "ghost-$(us)" get-doc anything
  expect_err "workspace_not_found" 4 "missing ws via -w → workspace_not_found"
}
