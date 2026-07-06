# shellcheck shell=bash
# Scoped tags (status:todo — one per scope per doc): creation,
# per-scope exclusivity on the doc write path, and card moves as
# retags. Kanban rendering itself now lives in views (340).

# The status scope comes seeded from the workspace template; tests
# only add the feature tag.
mk_board_tags() {
  run_cli -w "$1" create-tag --name feature-x --description "Feature X work."
}

test_scoped_tag_creation_and_validation() {
  local ws; ws="$(mk_workspace st-create)"
  run_cli -w "$ws" create-tag --name "stage:todo" --description "Stage: next up."
  expect_ok "scoped tag created"
  expect_eq ".tag.slug" "stage:todo" "slug echoed"

  run_cli -w "$ws" create-tag --name "a:b:c" --description "Two colons is not a scope."
  expect_err "tag_invalid" 2 "double-colon slug rejected"
}

test_scope_conflict_rejected_on_doc_write() {
  local ws; ws="$(mk_workspace st-conflict)"
  mk_board_tags "$ws"
  local blocks; blocks="[$(block_paragraph 'x')]"

  run_cli -w "$ws" create-doc --title "Contradiction" \
    --tag feature-x --tag "status:todo" --tag "status:done" --blocks "$blocks"
  expect_err "tag_scope_conflict" 2 "two status tags → tag_scope_conflict"

  run_cli -w "$ws" create-doc --title "Fine" \
    --tag feature-x --tag "status:todo" --blocks "$blocks"
  expect_ok "one tag per scope is fine"
}

test_moving_a_card_is_a_retag() {
  local ws; ws="$(mk_workspace st-move)"
  mk_board_tags "$ws"
  local blocks; blocks="[$(block_paragraph 'card')]"
  run_cli -w "$ws" create-doc --title "Card" --tag feature-x --tag "status:todo" --blocks "$blocks"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" apply-ops "$slug" --ops "[]" --intent "moved to doing" \
    --tag feature-x --tag "status:in-progress"
  expect_ok "retag ships a new version"
  expect_eq ".version_number" "2" "the move is versioned"

  run_cli -w "$ws" get-doc "$slug"
  if jq -e '.doc.tags | index("status:in-progress")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "card sits in the new column"
  else
    fail "retag didn't land"
  fi
}
