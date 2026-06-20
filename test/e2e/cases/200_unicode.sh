# shellcheck shell=bash
# Unicode + special characters — titles, bodies, summaries.

test_unicode_title_round_trips() {
  local ws; ws="$(mk_workspace ws-u-t)"
  local title="🚀 Démarrer rapidement"
  local blocks; blocks="[$(block_paragraph 'b')]"
  run_cli -w "$ws" create-doc --title "$title" --blocks "$blocks"
  expect_ok "create with unicode title"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.title" "$title" "title round-trips"
}

test_emoji_in_paragraph_round_trips() {
  local ws; ws="$(mk_workspace ws-u-emo)"
  local txt="🎉 ship it ✨"
  local blocks; blocks="[$(block_paragraph "$txt")]"
  run_cli -w "$ws" create-doc --title "Emoji" --blocks "$blocks"
  expect_ok "create with emoji body"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].content[0].text" "$txt" "emoji text preserved"
}

test_apostrophe_in_title_round_trips() {
  local ws; ws="$(mk_workspace ws-u-apos)"
  local title="Alice's Notes"
  local blocks; blocks="[$(block_paragraph 'b')]"
  run_cli -w "$ws" create-doc --title "$title" --blocks "$blocks"
  expect_ok "apostrophe title accepted"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.title" "$title" "apostrophe round-trips"
}

test_long_summary_accepted() {
  local ws; ws="$(mk_workspace ws-u-long)"
  # Server caps summary at 255; use exactly the max boundary.
  local summary
  summary="$(printf 'a%.0s' {1..255})"
  local blocks; blocks="[$(block_paragraph 'b')]"
  run_cli -w "$ws" create-doc --title "Long" --summary "$summary" --blocks "$blocks"
  expect_ok "boundary-length summary accepted"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local persisted; persisted="$(jq -r '.doc.summary' <<<"$LAST_OUT_TEXT")"
  if [[ "$persisted" == "$summary" ]]; then
    pass "max-length summary preserved verbatim"
  else
    fail "max-length summary mutated"
  fi
}

test_too_long_summary_rejected() {
  local ws; ws="$(mk_workspace ws-u-toolong)"
  # One over the limit.
  local summary
  summary="$(printf 'a%.0s' {1..256})"
  local blocks; blocks="[$(block_paragraph 'b')]"
  run_cli -w "$ws" create-doc --title "TooLong" --summary "$summary" --blocks "$blocks"
  expect_exit 2 "over-limit summary → validation_failed"
}

test_multibyte_in_code_block() {
  local ws; ws="$(mk_workspace ws-u-cb)"
  local body='println("héllo, 世界")'
  local blocks; blocks="[$(jq -nc --arg c "$body" '{type:"code", language:"rust", content:$c}')]"
  run_cli -w "$ws" create-doc --title "World" --blocks "$blocks"
  expect_ok "multibyte code accepted"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].content" "$body" "multibyte content preserved"
}

test_quote_in_comment_body() {
  local ws; ws="$(mk_workspace ws-u-cq)"
  local slug; slug="$(mk_doc "$ws" "X")"
  local body='quote: "this is critical" — done.'
  run_cli -w "$ws" create-comment "$slug" --body "$body"
  expect_ok "comment with quotes ok"
  run_cli -w "$ws" list-comments "$slug"
  if jq -e --arg b "$body" 'any(..|objects|.body? == $b)' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "quote-containing body round-trips"
  else
    fail "quotes in body got mangled"
  fi
}
