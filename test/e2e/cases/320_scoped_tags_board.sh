# shellcheck shell=bash
# Scoped tags (status:todo — one per scope per doc) and board blocks
# (a doc-embedded kanban: filter tags pick cards, a scope's tags are
# the columns, get-doc echoes a computed view).

# Creates the status scope + a feature tag in a workspace.
mk_board_tags() {
  local ws="$1"
  for t in "status:todo" "status:doing" "status:done"; do
    run_cli -w "$ws" create-tag --name "$t" --description "Board status column."
  done
  run_cli -w "$ws" create-tag --name feature-x --description "Feature X work."
}

test_scoped_tag_creation_and_validation() {
  local ws; ws="$(mk_workspace st-create)"
  run_cli -w "$ws" create-tag --name "status:todo" --description "Status: next up."
  expect_ok "scoped tag created"
  expect_eq ".tag.slug" "status:todo" "slug echoed"

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
    --tag feature-x --tag "status:doing"
  expect_ok "retag ships a new version"
  expect_eq ".version_number" "2" "the move is versioned"

  run_cli -w "$ws" get-doc "$slug"
  if jq -e '.doc.tags | index("status:doing")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "card sits in the new column"
  else
    fail "retag didn't land"
  fi
}

test_board_block_echoes_computed_view() {
  local ws; ws="$(mk_workspace st-board)"
  mk_board_tags "$ws"
  local blocks; blocks="[$(block_paragraph 'card')]"

  run_cli -w "$ws" create-doc --title "Todo card" --tag feature-x --tag "status:todo" --blocks "$blocks"
  run_cli -w "$ws" create-doc --title "Done card" --tag feature-x --tag "status:done" --blocks "$blocks"
  run_cli -w "$ws" create-doc --title "Unstatused card" --tag feature-x --blocks "$blocks"

  run_cli -w "$ws" create-doc --title "Feature X board" \
    --blocks "$(jq -nc '[{type: "board", tags: ["feature-x"], by: "status"}]')"
  expect_ok "board doc created"
  local board; board="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$board"
  expect_ok "get board doc"
  expect_eq '.doc.blocks[0].view.columns | length' "3" "columns from the status scope"
  expect_eq '.doc.blocks[0].view.columns[0]' "status:todo" "columns in creation order"
  expect_eq '.doc.blocks[0].view.cards | length' "3" "all filter matches are cards"
  expect_eq '.doc.blocks[0].view.cards | map(select(.column == null)) | length' "1" "unstatused card has null column"
}

test_board_over_unknown_tags_rejected() {
  local ws; ws="$(mk_workspace st-board-bad)"
  run_cli -w "$ws" create-doc --title "Bad board" \
    --blocks "$(jq -nc '[{type: "board", tags: ["ghost"], by: "status"}]')"
  expect_err "unknown_tags" 2 "board over unknown tags rejected"
}

test_board_forged_view_stripped() {
  local ws; ws="$(mk_workspace st-board-forge)"
  mk_board_tags "$ws"
  run_cli -w "$ws" create-doc --title "Forged" \
    --blocks "$(jq -nc '[{type: "board", tags: ["feature-x"], by: "status", view: {cards: [{title: "FORGED"}]}}]')"
  expect_ok "create with forged view accepted"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"

  run_cli -w "$ws" get-doc "$slug"
  expect_eq '.doc.blocks[0].view.cards | length' "0" "view is computed, not the pasted one"
}

test_list_docs_has_filter() {
  local ws; ws="$(mk_workspace st-has)"
  mk_board_tags "$ws"
  local blocks; blocks="[$(block_paragraph 'plain')]"
  run_cli -w "$ws" create-doc --title "Plain" --blocks "$blocks"
  local plain; plain="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" create-doc --title "A board" \
    --blocks "$(jq -nc '[{type: "board", tags: ["feature-x"], by: "status"}]')"
  run_cli -w "$ws" create-doc --title "A trail" \
    --blocks "$(jq -nc --arg doc "$plain" '[{type: "doc_link", doc: $doc}]')"

  run_cli -w "$ws" list-docs --has board
  expect_ok "list --has board ok"
  expect_count ".docs" "1" "one board"
  expect_eq ".docs[0].title" "A board" "the board"

  run_cli -w "$ws" list-docs --has links
  expect_ok "list --has links ok"
  expect_count ".docs" "1" "one trail"
  expect_eq ".docs[0].title" "A trail" "the trail"
}
