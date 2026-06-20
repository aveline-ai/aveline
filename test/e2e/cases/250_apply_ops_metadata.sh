# shellcheck shell=bash
# apply-ops metadata round-trips — title/summary/tags/pinned modifiable
# via apply-ops without re-creating the doc.

test_apply_ops_updates_title() {
  local ws; ws="$(mk_workspace ws-am-t)"
  local slug; slug="$(mk_doc "$ws" "OldTitle")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'x')" '{op:"append_block",block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --title "NewTitle"
  expect_ok "apply with new title"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.title" "NewTitle" "title updated"
}

test_apply_ops_updates_summary() {
  local ws; ws="$(mk_workspace ws-am-s)"
  local slug; slug="$(mk_doc "$ws" "X")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'x')" '{op:"append_block",block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --summary "now summarized"
  expect_ok "apply with new summary"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.summary" "now summarized" "summary updated"
}

test_apply_ops_updates_tags() {
  local ws; ws="$(mk_workspace ws-am-tg)"
  mk_tag "$ws" "alpha" >/dev/null
  mk_tag "$ws" "beta"  >/dev/null
  local slug; slug="$(mk_doc "$ws" "Tagged" "alpha")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'x')" '{op:"append_block",block:$b}')]"
  # Replace tag set with [beta]
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --tag beta
  expect_ok "apply with --tag beta"
  run_cli -w "$ws" get-doc "$slug"
  if jq -e '.doc.tags | (index("beta") and (index("alpha") | not))' \
       <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "tag set replaced"
  else
    fail "tag set not replaced"
  fi
}

test_apply_ops_pin_then_unpin() {
  local ws; ws="$(mk_workspace ws-am-pin)"
  local slug; slug="$(mk_doc "$ws" "Movable")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'x')" '{op:"append_block",block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --pin
  expect_ok "pin"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.pinned" "true" "pinned now"
  local ops2; ops2="[$(jq -nc --argjson b "$(block_paragraph 'y')" '{op:"append_block",block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops2" --unpin
  expect_ok "unpin"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.pinned" "false" "unpinned now"
}

test_apply_ops_no_metadata_preserves_current_values() {
  # Apply-ops with no --title/--summary/--tag should preserve previous
  # metadata.
  local ws; ws="$(mk_workspace ws-am-pres)"
  mk_tag "$ws" "stable" >/dev/null
  local blocks; blocks="[$(block_paragraph 'x')]"
  run_cli -w "$ws" create-doc --title "Persistent" --summary "stays" --tag stable --pin --blocks "$blocks"
  expect_ok "create"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'y')" '{op:"append_block",block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "apply no-meta"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.title" "Persistent" "title preserved"
  expect_eq ".doc.summary" "stays" "summary preserved"
  expect_eq ".doc.pinned" "true" "pinned preserved"
  if jq -e '.doc.tags | index("stable")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "tags preserved"
  else
    fail "tags lost"
  fi
}

test_apply_ops_intent_attached_to_new_version() {
  local ws; ws="$(mk_workspace ws-am-int)"
  local slug; slug="$(mk_doc "$ws" "I")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'x')" '{op:"append_block",block:$b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --intent "ship rationale"
  expect_ok "with intent"
  run_cli -w "$ws" get-version "$slug" 2
  expect_eq ".doc.intent" "ship rationale" "intent on v2"
}
