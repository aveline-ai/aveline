# shellcheck shell=bash
# apply-ops — every op type, every disposition path, version bumps.

# Helper: create a workspace+doc, return "ws/slug/first_block_id"
_setup_doc() {
  local ws; ws="$(mk_workspace ws-ops)"
  mk_tag "$ws" "ops" >/dev/null
  local blocks; blocks="[$(block_paragraph 'first body')]"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" create-doc --title "Apply" --tag ops --blocks "$blocks" \
    >"$LAST_OUT" 2>/dev/null || return 1
  local slug; slug="$(jq -r '.slug' <"$LAST_OUT")"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" get-doc "$slug" >"$LAST_OUT" 2>/dev/null
  local bid; bid="$(jq -r '.doc.blocks[0].id' <"$LAST_OUT")"
  printf "%s\n%s\n%s\n" "$ws" "$slug" "$bid"
}

test_apply_ops_append_block_bumps_version() {
  local lines; lines="$(_setup_doc)"
  local ws slug bid
  ws="$(sed -n 1p <<<"$lines")"
  slug="$(sed -n 2p <<<"$lines")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'appended')" \
    '{op: "append_block", block: $b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --intent "smoke append"
  expect_ok "append_block apply-ops ok"
  expect_eq ".version_number" "2" "version bumped to 2"
}

test_apply_ops_insert_block_after() {
  local lines; lines="$(_setup_doc)"
  local ws slug bid
  ws="$(sed -n 1p <<<"$lines")"
  slug="$(sed -n 2p <<<"$lines")"
  bid="$(sed -n 3p <<<"$lines")"
  local ops; ops="[$(jq -nc --arg after "$bid" --argjson b "$(block_paragraph 'inserted')" \
    '{op: "insert_block", after: $after, block: $b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "insert_block ok"
  run_cli -w "$ws" get-doc "$slug"
  expect_count ".doc.blocks" "2" "doc now has 2 blocks"
}

test_apply_ops_modify_block() {
  local lines; lines="$(_setup_doc)"
  local ws slug bid
  ws="$(sed -n 1p <<<"$lines")"
  slug="$(sed -n 2p <<<"$lines")"
  bid="$(sed -n 3p <<<"$lines")"
  local ops; ops="[$(jq -nc --arg id "$bid" \
    '{op: "modify_block", id: $id, patch: {content: [{text: "modified body"}]}}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "modify_block ok"
  run_cli -w "$ws" get-doc "$slug"
  if jq -e '.doc.blocks[0].content[0].text == "modified body"' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "block content reflects modify"
  else
    fail "block content did not change"
  fi
}

test_apply_ops_delete_block_with_safety() {
  # Deleting the ONLY block would orphan the doc. Add one first.
  local lines; lines="$(_setup_doc)"
  local ws slug bid
  ws="$(sed -n 1p <<<"$lines")"
  slug="$(sed -n 2p <<<"$lines")"
  bid="$(sed -n 3p <<<"$lines")"
  local ops_app; ops_app="[$(jq -nc --argjson b "$(block_paragraph 'keep')" \
    '{op: "append_block", block: $b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops_app"
  expect_ok "append before delete"
  local ops_del; ops_del="[$(jq -nc --arg id "$bid" '{op: "delete_block", id: $id}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops_del"
  expect_ok "delete_block ok"
  run_cli -w "$ws" get-doc "$slug"
  expect_count ".doc.blocks" "1" "one block remains"
}

test_apply_ops_move_block() {
  # Need at least two blocks.
  local lines; lines="$(_setup_doc)"
  local ws slug bid
  ws="$(sed -n 1p <<<"$lines")"
  slug="$(sed -n 2p <<<"$lines")"
  bid="$(sed -n 3p <<<"$lines")"
  local ops_app; ops_app="[$(jq -nc --argjson b "$(block_paragraph 'second')" \
    '{op: "append_block", block: $b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops_app"
  expect_ok "append second block"
  # Move first block to end (after the second one).
  run_cli -w "$ws" get-doc "$slug"
  local b2; b2="$(jq -r '.doc.blocks[1].id' <<<"$LAST_OUT_TEXT")"
  local ops_mv; ops_mv="[$(jq -nc --arg id "$bid" --arg after "$b2" \
    '{op: "move_block", id: $id, after: $after}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops_mv"
  expect_ok "move_block ok"
  run_cli -w "$ws" get-doc "$slug"
  local first_id; first_id="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  if [[ "$first_id" == "$b2" ]]; then
    pass "moved block now last (b2 is now first)"
  else
    fail "move did not reorder blocks"
  fi
}

test_apply_ops_missing_disposition_blocks() {
  # Set up a doc with an open comment on its only block; touching that
  # block without a disposition must fail.
  local ws; ws="$(mk_workspace ws-mdisp)"
  local blocks; blocks="[$(block_paragraph 'commented')]"
  run_cli -w "$ws" create-doc --title "C" --blocks "$blocks"
  expect_ok "doc created"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  # Bob is not a member yet — add him so he can comment.
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" \
    --block-id "$bid" --body "question?"
  expect_ok "bob's comment created"
  local ops; ops="[$(jq -nc --arg id "$bid" \
    '{op: "modify_block", id: $id, patch: {content: [{text: "edited"}]}}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_err "disposition_missing" 2 "modify touched block w/ open comment → disposition_missing"
}

test_apply_ops_disposition_resolve_with_reply() {
  local ws; ws="$(mk_workspace ws-dres)"
  local blocks; blocks="[$(block_paragraph 'orig')]"
  run_cli -w "$ws" create-doc --title "R" --blocks "$blocks"
  expect_ok "doc created"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" \
    --block-id "$bid" --body "fix it"
  expect_ok "bob commented"
  local cid; cid="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --arg id "$bid" \
    '{op: "modify_block", id: $id, patch: {content: [{text: "fixed"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" \
    '{comment_id: $cid, action: "resolve", reply: "addressed in next version"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_ok "resolve disposition accepted"
  expect_eq ".version_number" "2" "version bumped"
}

test_apply_ops_disposition_leave_with_note() {
  local ws; ws="$(mk_workspace ws-dlv)"
  local blocks; blocks="[$(block_paragraph 'leave-me')]"
  run_cli -w "$ws" create-doc --title "L" --blocks "$blocks"
  expect_ok "doc created"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" \
    --block-id "$bid" --body "still relevant"
  expect_ok "comment created"
  local cid; cid="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --arg id "$bid" \
    '{op: "modify_block", id: $id, patch: {content: [{text: "modified"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" \
    '{comment_id: $cid, action: "leave", note: "still open"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_ok "leave disposition ok"
}

test_apply_ops_disposition_invalid_action() {
  local ws; ws="$(mk_workspace ws-dinv)"
  local blocks; blocks="[$(block_paragraph 'x')]"
  run_cli -w "$ws" create-doc --title "I" --blocks "$blocks"
  expect_ok "doc created"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" \
    --block-id "$bid" --body "hmm"
  local cid; cid="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --arg id "$bid" \
    '{op: "modify_block", id: $id, patch: {content: [{text: "y"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" \
    '{comment_id: $cid, action: "do-the-thing"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_err "invalid_disposition_action" 2 "bad action → invalid_disposition_action"
}

test_apply_ops_disposition_leave_on_deleted_block() {
  local ws; ws="$(mk_workspace ws-dled)"
  local blocks; blocks="[$(block_paragraph 'doomed'),$(block_paragraph 'keeper')]"
  run_cli -w "$ws" create-doc --title "D" --blocks "$blocks"
  expect_ok "doc created"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" \
    --block-id "$bid" --body "comment on doomed"
  local cid; cid="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --arg id "$bid" '{op: "delete_block", id: $id}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" '{comment_id: $cid, action: "leave"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_err "leave_on_deleted_block" 2 "leave on deleted block → leave_on_deleted_block"
}

test_apply_ops_disposition_reanchor_missing_target() {
  local ws; ws="$(mk_workspace ws-drmt)"
  local blocks; blocks="[$(block_paragraph 'a'),$(block_paragraph 'b')]"
  run_cli -w "$ws" create-doc --title "RM" --blocks "$blocks"
  expect_ok "doc created"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" \
    --block-id "$bid" --body "comment"
  local cid; cid="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --arg id "$bid" \
    '{op: "modify_block", id: $id, patch: {content: [{text: "x"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" \
    '{comment_id: $cid, action: "reanchor", new_block_id: "b_does_not_exist"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_err "reanchor_target_missing" 2 "non-existent reanchor target → reanchor_target_missing"
}

test_apply_ops_duplicate_dispositions() {
  local ws; ws="$(mk_workspace ws-ddup)"
  local blocks; blocks="[$(block_paragraph 'x')]"
  run_cli -w "$ws" create-doc --title "Dup" --blocks "$blocks"
  expect_ok "doc created"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" \
    --block-id "$bid" --body "1"
  local cid; cid="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --arg id "$bid" \
    '{op: "modify_block", id: $id, patch: {content: [{text: "y"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" \
    '{comment_id: $cid, action: "resolve", reply: "first"}'),$(jq -nc --arg cid "$cid" \
    '{comment_id: $cid, action: "resolve", reply: "second"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_err "duplicate_dispositions" 2 "same comment twice → duplicate_dispositions"
}

test_apply_ops_doc_not_found() {
  local ws; ws="$(mk_workspace ws-opsnf)"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'x')" \
    '{op: "append_block", block: $b}')]"
  run_cli -w "$ws" apply-ops "ghost-$(us)" --ops "$ops"
  expect_err "not_found" 4 "apply-ops to missing doc → not_found"
}

test_apply_ops_can_update_title() {
  local lines; lines="$(_setup_doc)"
  local ws slug
  ws="$(sed -n 1p <<<"$lines")"
  slug="$(sed -n 2p <<<"$lines")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'x')" \
    '{op: "append_block", block: $b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --title "New Title"
  expect_ok "apply-ops with --title ok"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.title" "New Title" "title persisted"
}

test_apply_ops_unpin_via_flag() {
  local ws; ws="$(mk_workspace ws-opsup)"
  local blocks; blocks="[$(block_paragraph 'p')]"
  run_cli -w "$ws" create-doc --title "P" --pin --blocks "$blocks"
  expect_ok "pinned create"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'y')" \
    '{op: "append_block", block: $b}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --unpin
  expect_ok "apply-ops --unpin ok"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.pinned" "false" "doc is unpinned"
}
