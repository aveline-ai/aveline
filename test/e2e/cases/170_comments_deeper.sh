# shellcheck shell=bash
# Deeper comment behaviors — threads, edit versioning, lifecycle
# interactions with doc state.

test_comment_thread_three_deep() {
  local ws; ws="$(mk_workspace ws-c-deep)"
  local slug; slug="$(mk_doc "$ws" "Threaded")"
  local p1; p1="$(mk_comment "$ws" "$slug" "level 1")"
  run_cli -w "$ws" reply-comment "$slug" "$p1" --body "level 2"
  expect_ok "reply to level 1"
  local p2; p2="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" reply-comment "$slug" "$p2" --body "level 3"
  expect_ok "reply to level 2"
  local p3; p3="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  if [[ -n "$p3" && "$p3" != "null" ]]; then
    pass "three-deep thread id chain returned"
  else
    fail "couldn't create level 3 reply"
  fi
}

test_edit_comment_bumps_version_number() {
  local ws; ws="$(mk_workspace ws-c-vbump)"
  local slug; slug="$(mk_doc "$ws" "X")"
  local cid; cid="$(mk_comment "$ws" "$slug" "v1 body")"
  run_cli -w "$ws" list-comments "$slug"
  local v_before
  v_before="$(jq -r --arg c "$cid" \
    '[..|objects|select(.id? == $c)] | .[0].version_number' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" edit-comment "$cid" --body "v2 body"
  expect_ok "edit ok"
  run_cli -w "$ws" list-comments "$slug"
  local v_after
  v_after="$(jq -r --arg c "$cid" \
    '[..|objects|select(.id? == $c)] | .[0].version_number' <<<"$LAST_OUT_TEXT")"
  if [[ "$v_after" -gt "${v_before:-1}" ]]; then
    pass "version_number bumped (${v_before:-1} → $v_after)"
  else
    fail "version_number not bumped ($v_before → $v_after)"
  fi
}

test_edit_comment_preserves_id_changes_body() {
  local ws; ws="$(mk_workspace ws-c-pres)"
  local slug; slug="$(mk_doc "$ws" "X")"
  local cid; cid="$(mk_comment "$ws" "$slug" "original")"
  run_cli -w "$ws" edit-comment "$cid" --body "updated"
  expect_ok "edit ok"
  run_cli -w "$ws" list-comments "$slug"
  local body
  body="$(jq -r --arg c "$cid" \
    '[..|objects|select(.id? == $c)] | .[0].body' <<<"$LAST_OUT_TEXT")"
  if [[ "$body" == "updated" ]]; then
    pass "edited body reflects new content"
  else
    fail "body stale ('$body' != 'updated')"
  fi
}

test_resolve_then_delete_comment_keeps_resolved_state_visible() {
  local ws; ws="$(mk_workspace ws-c-rdel)"
  local slug; slug="$(mk_doc "$ws" "X")"
  local cid; cid="$(mk_comment "$ws" "$slug" "to resolve+delete")"
  run_cli -w "$ws" resolve-comment "$cid"
  expect_ok "resolve ok"
  run_cli -w "$ws" delete-comment "$cid"
  expect_ok "delete ok"
  # After delete, the comment shouldn't appear in default list.
  run_cli -w "$ws" list-comments "$slug"
  expect_ok "list-comments after delete"
  local hits
  hits="$(jq --arg c "$cid" \
    '[..|objects|select(.id? == $c and (.deleted_at? == null))] | length' \
    <<<"$LAST_OUT_TEXT")"
  if [[ "$hits" == "0" ]]; then
    pass "deleted comment hidden in default list"
  else
    fail "deleted comment still surfaced (count=$hits)"
  fi
}

test_undelete_comment_restores_visibility() {
  local ws; ws="$(mk_workspace ws-c-und)"
  local slug; slug="$(mk_doc "$ws" "X")"
  local cid; cid="$(mk_comment "$ws" "$slug" "to bounce")"
  run_cli -w "$ws" delete-comment "$cid"
  expect_ok "delete ok"
  run_cli -w "$ws" undelete-comment "$cid"
  expect_ok "undelete ok"
  run_cli -w "$ws" list-comments "$slug"
  local hits
  hits="$(jq --arg c "$cid" \
    '[..|objects|select(.id? == $c)] | length' <<<"$LAST_OUT_TEXT")"
  if [[ "$hits" -ge "1" ]]; then
    pass "undeleted comment back in list"
  else
    fail "undeleted comment missing"
  fi
}

test_reply_inherits_doc_anchor() {
  local ws; ws="$(mk_workspace ws-c-anc)"
  local slug; slug="$(mk_doc "$ws" "Anchor")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" create-comment "$slug" --block-id "$bid" --body "anchored parent"
  expect_ok "anchored create ok"
  local p; p="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" reply-comment "$slug" "$p" --body "reply"
  expect_ok "reply ok"
  run_cli -w "$ws" list-comments "$slug"
  local reply_block
  reply_block="$(jq -r --arg p "$p" \
    '[..|objects|select(.parent_comment_id? == $p)] | .[0].block_id' \
    <<<"$LAST_OUT_TEXT")"
  if [[ "$reply_block" == "$bid" ]]; then
    pass "reply inherits parent's block_id"
  else
    fail "reply block_id = $reply_block, expected $bid"
  fi
}

test_other_user_cannot_resolve_my_comment() {
  # Resolve is forbidden for non-authors? Actually the API allows
  # anyone in the workspace to resolve. Verify whichever way is
  # canonical — adjust if behavior changes.
  local ws; ws="$(mk_workspace ws-c-resown)"
  local slug; slug="$(mk_doc "$ws" "X")"
  add_member "$ws" "bob"
  local cid; cid="$(AVELINE_E2E_PERSONA=bob mk_comment "$ws" "$slug" "bob's")"
  run_cli -w "$ws" resolve-comment "$cid"
  # Currently allowed — assert success. If we tighten later, flip to
  # expect_err "forbidden" 3 ...
  expect_ok "alice can resolve bob's comment (workspace-level perm)"
}

test_delete_doc_hides_its_comments() {
  local ws; ws="$(mk_workspace ws-c-deldoc)"
  local slug; slug="$(mk_doc "$ws" "Doomed")"
  mk_comment "$ws" "$slug" "ephemeral" >/dev/null
  run_cli -w "$ws" delete-doc "$slug"
  expect_ok "doc deleted"
  # list-comments on a deleted doc should 404 (doc not found).
  run_cli -w "$ws" list-comments "$slug"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "comments on deleted doc → error"
  else
    fail "list-comments on deleted doc returned ok"
  fi
}

test_create_comment_with_empty_body_rejected() {
  local ws; ws="$(mk_workspace ws-c-mt)"
  local slug; slug="$(mk_doc "$ws" "X")"
  # Empty string body — cobra requires --body so it passes locally,
  # then server should reject.
  run_cli -w "$ws" create-comment "$slug" --body ""
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "empty body rejected"
  else
    fail "empty body accepted"
  fi
}
