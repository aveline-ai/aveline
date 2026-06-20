# shellcheck shell=bash
# Tag cascades — rename + delete should keep docs consistent.

test_rename_tag_updates_docs() {
  local ws; ws="$(mk_workspace ws-tc-ren)"
  mk_tag "$ws" "old-name" >/dev/null
  local slug; slug="$(mk_doc "$ws" "Tagged" "old-name")"
  run_cli -w "$ws" edit-tag "old-name" --name "new-name"
  expect_ok "rename ok"
  run_cli -w "$ws" get-doc "$slug"
  expect_ok "fetch tagged doc"
  if jq -e '.doc.tags | index("new-name")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "doc now has new tag name"
  else
    fail "rename didn't cascade into doc.tags"
  fi
  if jq -e '.doc.tags | index("old-name") | not' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "old tag name removed from doc"
  else
    fail "old tag name still on doc"
  fi
}

test_delete_unused_tag_succeeds() {
  local ws; ws="$(mk_workspace ws-tc-delu)"
  mk_tag "$ws" "unused" >/dev/null
  run_cli -w "$ws" delete-tag "unused"
  expect_ok "delete unused tag ok"
  run_cli -w "$ws" list-tags
  if jq -e '.tags | map(.slug // .name) | index("unused") | not' \
       <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "deleted tag gone from list"
  else
    fail "deleted tag still listed"
  fi
}

test_delete_tag_blocked_when_only_tag_on_a_doc() {
  local ws; ws="$(mk_workspace ws-tc-only)"
  mk_tag "$ws" "lone" >/dev/null
  mk_doc "$ws" "MonoTag" "lone" >/dev/null
  run_cli -w "$ws" delete-tag "lone"
  expect_err "would_orphan_docs" 2 "blocked"
}

test_delete_tag_succeeds_after_doc_retagged() {
  local ws; ws="$(mk_workspace ws-tc-retag)"
  mk_tag "$ws" "first"  >/dev/null
  mk_tag "$ws" "second" >/dev/null
  local slug; slug="$(mk_doc "$ws" "Doc" "first")"
  # Add a second tag via apply-ops --tag (replaces the list).
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'x')" '{op:"append_block",block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --tag first --tag second
  expect_ok "doc retagged with both"
  # Now deleting `first` should succeed (doc still has `second`).
  run_cli -w "$ws" delete-tag "first"
  expect_ok "delete first ok (doc keeps second)"
}

test_create_doc_with_unknown_tag_fails() {
  local ws; ws="$(mk_workspace ws-tc-unk)"
  local blocks; blocks="[$(block_paragraph 'b')]"
  run_cli -w "$ws" create-doc --title "X" --tag ghosttag --blocks "$blocks"
  expect_err "unknown_tags" 2 "tag must exist first"
}
