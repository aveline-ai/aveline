# shellcheck shell=bash
# Input forms — every body-like flag accepts:
#   • raw value inline
#   • a file path
#   • "-" for stdin
# Equivalent results across all three.

test_blocks_inline_vs_file_produce_equal_docs() {
  local ws; ws="$(mk_workspace ws-i-bf)"
  local blocks; blocks="[$(block_paragraph 'same body')]"
  # Inline
  run_cli -w "$ws" create-doc --title "Inline" --blocks "$blocks"
  expect_ok "inline create ok"
  local slug_inline; slug_inline="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  # File
  local f; f="$(mktemp)"; printf '%s' "$blocks" > "$f"
  run_cli -w "$ws" create-doc --title "FromFile" --blocks "$f"
  expect_ok "file create ok"
  local slug_file; slug_file="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  rm -f "$f"
  # Both docs should have the same first-block text.
  run_cli -w "$ws" get-doc "$slug_inline"
  local txt_a; txt_a="$(jq -r '.doc.blocks[0].content[0].text' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug_file"
  local txt_b; txt_b="$(jq -r '.doc.blocks[0].content[0].text' <<<"$LAST_OUT_TEXT")"
  if [[ "$txt_a" == "$txt_b" && "$txt_a" == "same body" ]]; then
    pass "inline & file produce equal block content"
  else
    fail "mismatch: inline='$txt_a' file='$txt_b'"
  fi
}

test_blocks_stdin_produces_same_doc() {
  local ws; ws="$(mk_workspace ws-i-stdin)"
  local blocks; blocks="[$(block_paragraph 'piped')]"
  LAST_OUT="$(mktemp)"; LAST_ERR="$(mktemp)"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" create-doc --title "Piped" --blocks - <<<"$blocks" \
    >"$LAST_OUT" 2>"$LAST_ERR"
  LAST_EXIT=$?
  LAST_OUT_TEXT="$(cat "$LAST_OUT")"; LAST_ERR_TEXT="$(cat "$LAST_ERR")"
  expect_ok "stdin create ok"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].content[0].text" "piped" "stdin body persisted"
}

test_ops_file_input_works() {
  local ws; ws="$(mk_workspace ws-i-ofile)"
  local slug; slug="$(mk_doc "$ws" "Target")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'appended via file')" \
    '{op:"append_block", block:$b}')]"
  local f; f="$(mktemp)"; printf '%s' "$ops" > "$f"
  run_cli -w "$ws" apply-ops "$slug" --ops "$f"
  expect_ok "ops via file ok"
  rm -f "$f"
}

test_ops_stdin_input_works() {
  local ws; ws="$(mk_workspace ws-i-ostdin)"
  local slug; slug="$(mk_doc "$ws" "Target")"
  local ops; ops="[$(jq -nc --argjson b "$(block_paragraph 'appended via stdin')" \
    '{op:"append_block", block:$b}')]"
  LAST_OUT="$(mktemp)"; LAST_ERR="$(mktemp)"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" apply-ops "$slug" --ops - <<<"$ops" \
    >"$LAST_OUT" 2>"$LAST_ERR"
  LAST_EXIT=$?
  LAST_OUT_TEXT="$(cat "$LAST_OUT")"; LAST_ERR_TEXT="$(cat "$LAST_ERR")"
  expect_ok "ops via stdin ok"
}

test_comment_body_via_at_file() {
  local ws; ws="$(mk_workspace ws-i-cat)"
  local slug; slug="$(mk_doc "$ws" "T")"
  local f; f="$(mktemp)"; printf "from file body" > "$f"
  run_cli -w "$ws" create-comment "$slug" --body "@$f"
  expect_ok "comment body @file ok"
  rm -f "$f"
  run_cli -w "$ws" list-comments "$slug"
  if jq -e 'any(..|objects|.body? == "from file body")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "file body round-trips into comment list"
  else
    fail "file body missing from list"
  fi
}

test_comment_body_via_stdin() {
  local ws; ws="$(mk_workspace ws-i-cstdin)"
  local slug; slug="$(mk_doc "$ws" "T")"
  LAST_OUT="$(mktemp)"; LAST_ERR="$(mktemp)"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" create-comment "$slug" --body - <<<"piped comment body" \
    >"$LAST_OUT" 2>"$LAST_ERR"
  LAST_EXIT=$?
  LAST_OUT_TEXT="$(cat "$LAST_OUT")"; LAST_ERR_TEXT="$(cat "$LAST_ERR")"
  expect_ok "stdin comment body ok"
}

test_dispositions_from_file() {
  local ws; ws="$(mk_workspace ws-i-dfile)"
  local blocks; blocks="[$(block_paragraph 'a')]"
  run_cli -w "$ws" create-doc --title "D" --blocks "$blocks"
  expect_ok "create doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  local b0; b0="$(jq -r '.doc.blocks[0].id' <<<"$LAST_OUT_TEXT")"
  add_member "$ws" "bob"
  local cid; cid="$(AVELINE_E2E_PERSONA=bob mk_comment "$ws" "$slug" "fix")"
  local ops; ops="[$(jq -nc --arg id "$b0" \
    '{op:"modify_block",id:$id,patch:{content:[{text:"y"}]}}')]"
  local disp; disp="[$(jq -nc --arg cid "$cid" \
    '{comment_id:$cid,action:"resolve",reply:"shipped"}')]"
  local opsf dispf
  opsf="$(mktemp)";  printf '%s' "$ops"  > "$opsf"
  dispf="$(mktemp)"; printf '%s' "$disp" > "$dispf"
  run_cli -w "$ws" apply-ops "$slug" --ops "$opsf" --dispositions "$dispf"
  expect_ok "ops + dispositions via files"
  rm -f "$opsf" "$dispf"
}

test_blocks_invalid_json_in_file_fails() {
  local ws; ws="$(mk_workspace ws-i-bj)"
  local f; f="$(mktemp)"; printf "{ not json" > "$f"
  run_cli -w "$ws" create-doc --title "Bad" --blocks "$f"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "invalid JSON file rejected"
  else
    fail "invalid JSON file accepted"
  fi
  rm -f "$f"
}
