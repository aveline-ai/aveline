# shellcheck shell=bash
# Workspace orientation doc — well-known slug ("agents"), seeded at
# workspace creation, undeletable, fetchable via get-orientation.

test_orientation_seeded_on_workspace_create() {
  local ws; ws="$(mk_workspace orient-seed)"
  run_cli -w "$ws" get-orientation
  expect_ok "get-orientation on a fresh workspace"
  expect_eq '.doc.slug' "agents" "well-known slug"
  expect_eq '.doc.pinned' "true" "seeded pinned"
  expect_eq '.doc.version_number' "1" "fresh template at v1"
}

test_orientation_appears_in_list_docs() {
  local ws; ws="$(mk_workspace orient-list)"
  run_cli -w "$ws" list-docs
  expect_ok "list-docs ok"
  if jq -e '.docs | map(.slug) | index("agents")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "orientation doc shows up in the normal list"
  else
    fail "orientation doc missing from list-docs"
  fi
}

test_orientation_cannot_be_deleted() {
  local ws; ws="$(mk_workspace orient-del)"
  run_cli -w "$ws" delete-doc agents
  expect_err "orientation_undeletable" 2 "delete rejected with orientation_undeletable"
  run_cli -w "$ws" get-orientation
  expect_ok "orientation still there after delete attempt"
}

test_orientation_is_editable() {
  local ws; ws="$(mk_workspace orient-edit)"
  run_cli -w "$ws" apply-ops agents --intent "fill in conventions" \
    --ops "[$(jq -nc '{op: "append_block", block: {type: "paragraph", content: [{text: "we ship on fridays"}]}}')]"
  expect_ok "apply-ops on orientation doc"
  expect_eq '.version_number' "2" "new version minted"
}

test_orientation_follow_expands_doc_links() {
  local ws; ws="$(mk_workspace orient-follow)"
  local target; target="$(mk_doc "$ws" "First stop")"

  run_cli -w "$ws" apply-ops agents --intent "add first stop" \
    --ops "$(jq -nc --arg doc "$target" \
      '[{op: "append_block", block: {type: "doc_link", doc: $doc}}]')"
  expect_ok "doc_link added to orientation"

  run_cli -w "$ws" get-orientation --follow
  expect_ok "get-orientation --follow ok"
  expect_eq '.linked_docs | length' "1" "one linked doc"
  expect_eq '.linked_docs[0].slug' "$target" "follow pulls the stop"
}
