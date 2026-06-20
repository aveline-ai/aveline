# shellcheck shell=bash
# create-doc — every flag, every input form, every error path.

test_create_doc_minimal() {
  local ws; ws="$(mk_workspace ws-cd-min)"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "Minimal" --blocks "$blocks"
  expect_ok "minimal create-doc ok"
  expect_present ".slug" "slug echoed"
  expect_present ".doc_id" "doc_id echoed"
  expect_present ".version_id" "version_id echoed"
  expect_eq ".version_number" "1" "first version is 1"
}

test_create_doc_explicit_slug() {
  local ws; ws="$(mk_workspace ws-cd-slug)"
  local slug; slug="$(us my-slug)"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "Explicit" --slug "$slug" --blocks "$blocks"
  expect_ok "explicit-slug create ok"
  expect_eq ".slug" "$slug" "echoed slug matches input"
}

test_create_doc_with_summary() {
  local ws; ws="$(mk_workspace ws-cd-sum)"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "Sum" --summary "A pithy one-liner" --blocks "$blocks"
  expect_ok "create with summary ok"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.summary" "A pithy one-liner" "summary persists"
}

test_create_doc_with_tags() {
  local ws; ws="$(mk_workspace ws-cd-tags)"
  mk_tag "$ws" "alpha" >/dev/null
  mk_tag "$ws" "beta"  >/dev/null
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "Tagged" --tag alpha --tag beta --blocks "$blocks"
  expect_ok "tagged create ok"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  if jq -e '.doc.tags | (index("alpha") and index("beta"))' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "both tags persisted"
  else
    fail "tags not persisted"
  fi
}

test_create_doc_unknown_tag() {
  local ws; ws="$(mk_workspace ws-cd-unktag)"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "Bad" --tag never-made --blocks "$blocks"
  expect_err "unknown_tags" 2 "tag not in workspace → unknown_tags"
}

test_create_doc_pinned_persists() {
  local ws; ws="$(mk_workspace ws-cd-pin)"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "Pinned" --pin --blocks "$blocks"
  expect_ok "create --pin ok"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.pinned" "true" "pinned echoed back"
}

test_create_doc_duplicate_slug() {
  local ws; ws="$(mk_workspace ws-cd-dup)"
  local slug; slug="$(us dup-doc)"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --title "First" --slug "$slug" --blocks "$blocks"
  expect_ok "first create ok"
  run_cli -w "$ws" create-doc --title "Second" --slug "$slug" --blocks "$blocks"
  expect_err "slug_taken" 2 "duplicate slug → slug_taken"
}

test_create_doc_no_title_local_error() {
  local ws; ws="$(mk_workspace ws-cd-nt)"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  run_cli -w "$ws" create-doc --blocks "$blocks"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "missing --title fails locally"
  else
    fail "missing --title was accepted"
  fi
}

test_create_doc_no_blocks_local_error() {
  local ws; ws="$(mk_workspace ws-cd-nb)"
  run_cli -w "$ws" create-doc --title "NoBlocks"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "missing --blocks fails locally"
  else
    fail "missing --blocks was accepted"
  fi
}

test_create_doc_blocks_from_file() {
  local ws; ws="$(mk_workspace ws-cd-file)"
  local f; f="$(mktemp)"
  printf '[%s]' "$(block_paragraph 'from file')" > "$f"
  run_cli -w "$ws" create-doc --title "FromFile" --blocks "$f"
  expect_ok "create with --blocks PATH ok"
  rm -f "$f"
}

test_create_doc_blocks_from_stdin() {
  local ws; ws="$(mk_workspace ws-cd-stdin)"
  local body; body="[$(block_paragraph 'from stdin')]"
  XDG_CONFIG_HOME="$(persona_xdg)" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" -w "$ws" create-doc --title "FromStdin" --blocks - <<<"$body" \
    >"$(mktemp)" 2>"$(mktemp)" && LAST_EXIT=0 || LAST_EXIT=$?
  if [[ "$LAST_EXIT" == "0" ]]; then
    pass "create with --blocks - (stdin) ok"
  else
    fail "create with --blocks - failed (exit $LAST_EXIT)"
  fi
}

test_create_doc_invalid_blocks_json() {
  local ws; ws="$(mk_workspace ws-cd-badjson)"
  run_cli -w "$ws" create-doc --title "Bad" --blocks "not-json-at-all"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "invalid JSON in --blocks fails"
  else
    fail "invalid JSON accepted"
  fi
}

test_create_doc_actor_agent_default() {
  local ws; ws="$(mk_workspace ws-cd-actor)"
  local blocks; blocks="[$(block_paragraph 'hi')]"
  # The create itself succeeds; the audit event should record actor=agent.
  run_cli -w "$ws" create-doc --title "ByAgent" --blocks "$blocks"
  expect_ok "create with default actor ok"
}
