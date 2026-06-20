# shellcheck shell=bash
# apply-ops disposition happy paths — every action type round-trips
# through the API and surfaces the right downstream state.

# _doc_with_comment <persona_for_comment> <ws-label-prefix>
# Creates: workspace + 2-block doc (touched + untouched) + bob comment
# on block 0. Echoes "ws\nslug\nbid_touched\nbid_untouched\ncomment_id".
_doc_with_comment() {
  local commenter="${1:-bob}"
  local label="${2:-ws-disp}"
  local ws; ws="$(mk_workspace "$label")"
  local blocks; blocks="[$(block_paragraph 'commented'),$(block_paragraph 'untouched')]"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" create-doc --title "DispDoc" --blocks "$blocks" \
    >"$LAST_OUT" 2>/dev/null || return 1
  local slug; slug="$(jq -r '.slug' <"$LAST_OUT")"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" get-doc "$slug" >"$LAST_OUT" 2>/dev/null
  local b0; b0="$(jq -r '.doc.blocks[0].id' <"$LAST_OUT")"
  local b1; b1="$(jq -r '.doc.blocks[1].id' <"$LAST_OUT")"
  add_member "$ws" "$commenter"
  AVELINE_E2E_PERSONA="$commenter" \
    XDG_CONFIG_HOME="$(persona_xdg "$commenter")" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" create-comment "$slug" --block-id "$b0" --body "fix this please" \
    >"$LAST_OUT" 2>/dev/null
  local cid; cid="$(jq -r '.id' <"$LAST_OUT")"
  printf "%s\n%s\n%s\n%s\n%s\n" "$ws" "$slug" "$b0" "$b1" "$cid"
}

test_disposition_resolve_records_reply() {
  local lines; lines="$(_doc_with_comment bob ws-d-res)"
  local ws slug b0 b1 cid
  ws="$(sed -n 1p <<<"$lines")"; slug="$(sed -n 2p <<<"$lines")"
  b0="$(sed -n 3p <<<"$lines")";  cid="$(sed -n 5p <<<"$lines")"
  local ops; ops="[$(jq -nc --arg id "$b0" \
    '{op:"modify_block", id:$id, patch:{content:[{text:"fixed"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" \
    '{comment_id:$cid, action:"resolve", reply:"addressed in v2"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_ok "resolve disposition shipped"
  expect_eq ".version_number" "2" "version bumped"
  # Comment should now show resolved_at and have a child reply.
  run_cli -w "$ws" list-comments "$slug"
  expect_ok "list-comments after resolve"
  local resolved; resolved="$(jq -r --arg c "$cid" \
    '[..|objects|select(.id? == $c)] | .[0].resolved_at' <<<"$LAST_OUT_TEXT")"
  if [[ -n "$resolved" && "$resolved" != "null" ]]; then
    pass "parent comment is resolved (resolved_at set)"
  else
    fail "parent comment not resolved"
  fi
}

test_disposition_reanchor_keeps_comment_open() {
  local lines; lines="$(_doc_with_comment bob ws-d-rea)"
  local ws slug b0 b1 cid
  ws="$(sed -n 1p <<<"$lines")"; slug="$(sed -n 2p <<<"$lines")"
  b0="$(sed -n 3p <<<"$lines")"; b1="$(sed -n 4p <<<"$lines")"
  cid="$(sed -n 5p <<<"$lines")"
  local ops; ops="[$(jq -nc --arg id "$b0" \
    '{op:"modify_block", id:$id, patch:{content:[{text:"refactored"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" --arg target "$b1" \
    '{comment_id:$cid, action:"reanchor", new_block_id:$target, note:"split off"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_ok "reanchor disposition shipped"
  run_cli -w "$ws" list-comments "$slug"
  expect_ok "list-comments after reanchor"
  # Comment still unresolved, but pinned to b1 now.
  local block_id resolved
  block_id="$(jq -r --arg c "$cid" \
    '[..|objects|select(.id? == $c)] | .[0].block_id' <<<"$LAST_OUT_TEXT")"
  resolved="$(jq -r --arg c "$cid" \
    '[..|objects|select(.id? == $c)] | .[0].resolved_at' <<<"$LAST_OUT_TEXT")"
  if [[ "$block_id" == "$b1" ]]; then
    pass "comment reanchored to b1"
  else
    fail "comment block_id = $block_id, expected $b1"
  fi
  if [[ -z "$resolved" || "$resolved" == "null" ]]; then
    pass "comment still unresolved"
  else
    fail "comment was incorrectly resolved"
  fi
}

test_disposition_mixed_in_single_apply_ops() {
  # Two comments on two different blocks, one resolved and one reanchored
  # in the same apply-ops.
  local ws; ws="$(mk_workspace ws-d-mix)"
  local blocks; blocks="[$(block_paragraph 'a'),$(block_paragraph 'b'),$(block_paragraph 'c')]"
  run_cli -w "$ws" create-doc --title "Mix" --blocks "$blocks"
  expect_ok "create 3-block doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local ba bb bc
  ba="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  bb="$(jq -r '.doc.blocks[1].id' <<<"$LAST_OUT_TEXT")"
  bc="$(jq -r '.doc.blocks[2].id' <<<"$LAST_OUT_TEXT")"
  add_member "$ws" "bob"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" --block-id "$ba" --body "a-comment"
  local ca; ca="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  AVELINE_E2E_PERSONA=bob run_cli -w "$ws" create-comment "$slug" --block-id "$bb" --body "b-comment"
  local cb; cb="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  local ops; ops="[$(jq -nc --arg a "$ba" '{op:"modify_block",id:$a,patch:{content:[{text:"a2"}]}}'),$(jq -nc --arg b "$bb" '{op:"modify_block",id:$b,patch:{content:[{text:"b2"}]}}')]"
  local disp; disp="[$(jq -nc --arg id "$ca" '{comment_id:$id,action:"resolve",reply:"done"}'),$(jq -nc --arg id "$cb" --arg t "$bc" '{comment_id:$id,action:"reanchor",new_block_id:$t}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_ok "mixed dispositions shipped together"
  expect_eq ".version_number" "2" "single version bump"
}

test_disposition_leave_keeps_comment() {
  # Modify block on which there's a leave-disposition'd comment.
  local lines; lines="$(_doc_with_comment bob ws-d-lv)"
  local ws slug b0 cid
  ws="$(sed -n 1p <<<"$lines")"; slug="$(sed -n 2p <<<"$lines")"
  b0="$(sed -n 3p <<<"$lines")";  cid="$(sed -n 5p <<<"$lines")"
  local ops; ops="[$(jq -nc --arg id "$b0" \
    '{op:"modify_block", id:$id, patch:{content:[{text:"changed"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" \
    '{comment_id:$cid, action:"leave", note:"still relevant"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  expect_ok "leave disposition shipped"
  run_cli -w "$ws" list-comments "$slug"
  expect_ok "list-comments after leave"
  local resolved; resolved="$(jq -r --arg c "$cid" \
    '[..|objects|select(.id? == $c)] | .[0].resolved_at' <<<"$LAST_OUT_TEXT")"
  if [[ -z "$resolved" || "$resolved" == "null" ]]; then
    pass "leave keeps comment open"
  else
    fail "leave incorrectly resolved comment"
  fi
}

test_disposition_resolve_without_reply_errors() {
  # `resolve` action requires a non-empty reply (per the comments
  # context). Send without one — must error.
  local lines; lines="$(_doc_with_comment bob ws-d-noreply)"
  local ws slug b0 cid
  ws="$(sed -n 1p <<<"$lines")"; slug="$(sed -n 2p <<<"$lines")"
  b0="$(sed -n 3p <<<"$lines")";  cid="$(sed -n 5p <<<"$lines")"
  local ops; ops="[$(jq -nc --arg id "$b0" \
    '{op:"modify_block", id:$id, patch:{content:[{text:"x"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" '{comment_id:$cid, action:"resolve"}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops" --dispositions "$disp"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "resolve without reply rejected"
  else
    fail "resolve accepted with no reply"
  fi
}

test_apply_ops_no_disposition_needed_if_untouched_block() {
  # Comment on block 1; modify block 0 — should NOT require a
  # disposition (only touched blocks).
  local lines; lines="$(_doc_with_comment bob ws-d-untouched)"
  local ws slug b0 b1 cid
  ws="$(sed -n 1p <<<"$lines")"; slug="$(sed -n 2p <<<"$lines")"
  b0="$(sed -n 3p <<<"$lines")"; b1="$(sed -n 4p <<<"$lines")"
  cid="$(sed -n 5p <<<"$lines")"
  # Comment is on b0; modify b1 instead → no disposition needed.
  local ops; ops="[$(jq -nc --arg id "$b1" \
    '{op:"modify_block", id:$id, patch:{content:[{text:"new untouched"}]}}')]"
  run_cli -w "$ws" apply-ops "$slug" --ops "$ops"
  expect_ok "modify of unrelated block requires no disposition"
}
