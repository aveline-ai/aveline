# shellcheck shell=bash
# Comments — create, reply, edit, delete, undelete, resolve, unresolve,
# author-only auth.

test_create_comment_doc_level() {
  local ws; ws="$(mk_workspace ws-c-doc)"
  local slug; slug="$(mk_doc "$ws" "ForComments")"
  run_cli -w "$ws" create-comment "$slug" --body "doc-level note"
  expect_ok "doc-level comment create ok"
  expect_present ".id" "id echoed"
}

test_create_comment_anchored_to_block() {
  local ws; ws="$(mk_workspace ws-c-anchor)"
  local slug; slug="$(mk_doc "$ws" "Anchored")"
  run_cli -w "$ws" get-doc "$slug"
  local bid; bid="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" create-comment "$slug" --block-id "$bid" --body "anchored"
  expect_ok "anchored comment create ok"
  expect_present ".id" "id echoed"
}

test_create_comment_missing_body_local_error() {
  local ws; ws="$(mk_workspace ws-c-nobody)"
  local slug; slug="$(mk_doc "$ws" "X")"
  run_cli -w "$ws" create-comment "$slug"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "missing --body fails locally"
  else
    fail "missing --body accepted"
  fi
}

test_create_comment_unknown_doc() {
  local ws; ws="$(mk_workspace ws-c-undoc)"
  run_cli -w "$ws" create-comment "ghost-$(us)" --body "hi"
  expect_err "not_found" 4 "comment on missing doc → not_found"
}

test_reply_comment_threads() {
  local ws; ws="$(mk_workspace ws-c-reply)"
  local slug; slug="$(mk_doc "$ws" "Threaded")"
  local cid; cid="$(mk_comment "$ws" "$slug" "parent")"
  run_cli -w "$ws" reply-comment "$slug" "$cid" --body "child"
  expect_ok "reply ok"
  expect_present ".id" "reply id echoed"
}

test_list_comments_returns_both_thread_levels() {
  local ws; ws="$(mk_workspace ws-c-list)"
  local slug; slug="$(mk_doc "$ws" "L")"
  local cid; cid="$(mk_comment "$ws" "$slug" "first")"
  run_cli -w "$ws" reply-comment "$slug" "$cid" --body "reply" >/dev/null
  run_cli -w "$ws" list-comments "$slug"
  expect_ok "list-comments ok"
  # The list should include both — exact shape (flat vs threaded)
  # depends on the API; we just assert ≥ 2 entries surfaced anywhere.
  local count
  count="$(jq '[.. | objects | select(.body? != null)] | length' <<<"$LAST_OUT_TEXT")"
  if [[ "$count" -ge 2 ]]; then
    pass "list contains parent + reply ($count objects with body)"
  else
    fail "list missing replies (count=$count)"
  fi
}

test_edit_own_comment() {
  local ws; ws="$(mk_workspace ws-c-edit)"
  local slug; slug="$(mk_doc "$ws" "E")"
  local cid; cid="$(mk_comment "$ws" "$slug" "before edit")"
  run_cli -w "$ws" edit-comment "$cid" --body "after edit"
  expect_ok "edit own comment ok"
}

test_edit_other_users_comment_forbidden() {
  local ws; ws="$(mk_workspace ws-c-editforbid)"
  local slug; slug="$(mk_doc "$ws" "EF")"
  add_member "$ws" "bob"
  local cid; cid="$(AVELINE_E2E_PERSONA=bob mk_comment "$ws" "$slug" "bob's note")"
  # Alice (default) tries to edit bob's comment.
  run_cli -w "$ws" edit-comment "$cid" --body "alice tries"
  expect_err "forbidden" 3 "non-author edit → forbidden"
}

test_delete_own_comment() {
  local ws; ws="$(mk_workspace ws-c-del)"
  local slug; slug="$(mk_doc "$ws" "D")"
  local cid; cid="$(mk_comment "$ws" "$slug" "to delete")"
  run_cli -w "$ws" delete-comment "$cid"
  expect_ok "delete own comment ok"
}

test_delete_other_users_comment_forbidden() {
  local ws; ws="$(mk_workspace ws-c-delforbid)"
  local slug; slug="$(mk_doc "$ws" "DF")"
  add_member "$ws" "bob"
  local cid; cid="$(AVELINE_E2E_PERSONA=bob mk_comment "$ws" "$slug" "bob's")"
  run_cli -w "$ws" delete-comment "$cid"
  expect_err "forbidden" 3 "non-author delete → forbidden"
}

test_undelete_restores_comment() {
  local ws; ws="$(mk_workspace ws-c-und)"
  local slug; slug="$(mk_doc "$ws" "U")"
  local cid; cid="$(mk_comment "$ws" "$slug" "again")"
  run_cli -w "$ws" delete-comment "$cid"
  expect_ok "delete ok"
  run_cli -w "$ws" undelete-comment "$cid"
  expect_ok "undelete ok"
}

test_resolve_then_unresolve_comment() {
  local ws; ws="$(mk_workspace ws-c-res)"
  local slug; slug="$(mk_doc "$ws" "RE")"
  local cid; cid="$(mk_comment "$ws" "$slug" "open thread")"
  run_cli -w "$ws" resolve-comment "$cid"
  expect_ok "resolve ok"
  run_cli -w "$ws" unresolve-comment "$cid"
  expect_ok "unresolve ok"
}

test_edit_comment_not_found() {
  local ws; ws="$(mk_workspace ws-c-enf)"
  run_cli -w "$ws" edit-comment "00000000-0000-0000-0000-000000000000" --body "x"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "edit on missing comment errors"
  else
    fail "edit on missing comment unexpectedly succeeded"
  fi
}
