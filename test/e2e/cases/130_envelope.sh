# shellcheck shell=bash
# Envelope — cross-cutting contract checks.
#
# Every success has ok:true at top level.
# Every error has ok:false at top level with a nested {error:{code,message}}.
# Exit codes group errors: 2 validation, 3 auth, 4 not-found, 1 other.

test_envelope_success_has_ok_true() {
  local ws; ws="$(mk_workspace ws-env-ok)"
  run_cli -w "$ws" list-docs
  expect_eq ".ok" "true" "success envelope has ok:true"
}

test_envelope_success_payload_at_top_level() {
  local ws; ws="$(mk_workspace ws-env-payload)"
  run_cli -w "$ws" list-docs
  expect_present ".docs" "list-docs payload at top level"
  expect_absent ".data" "no .data wrapper"
}

test_envelope_error_has_ok_false_and_code() {
  run_cli -w "ghost-$(us)" list-docs
  if [[ "$LAST_EXIT" == "0" ]]; then fail "expected non-zero"; return; fi
  # Error envelope goes to stderr.
  local ok code
  ok="$(jq -r '.ok' <<<"$LAST_ERR_TEXT" 2>/dev/null)"
  code="$(jq -r '.error.code' <<<"$LAST_ERR_TEXT" 2>/dev/null)"
  if [[ "$ok" == "false" ]]; then pass "error envelope ok:false"; else fail "stderr not ok:false (got: $LAST_ERR_TEXT)"; fi
  if [[ -n "$code" && "$code" != "null" ]]; then pass "error has .error.code"; else fail "error missing code"; fi
}

test_envelope_error_has_message() {
  run_cli -w "ghost-$(us)" list-docs
  local msg; msg="$(jq -r '.error.message' <<<"$LAST_ERR_TEXT" 2>/dev/null)"
  if [[ -n "$msg" && "$msg" != "null" ]]; then
    pass "error has .error.message"
  else
    fail "error missing .error.message"
  fi
}

test_exit_code_2_for_validation() {
  local ws; ws="$(mk_workspace ws-exit2)"
  # Server-side validation: invalid tag slug. (--description present so
  # we don't trigger client-side cobra "required flag" error first.)
  run_cli -w "$ws" create-tag --name "Has Spaces" --description "valid description here"
  expect_exit 2 "server validation error exits 2"
}

test_exit_code_3_for_auth() {
  # Force unauthorized via a bogus token using a temp config.
  local tmp; tmp="$(mktemp -d)"; mkdir -p "$tmp/aveline"
  cat > "$tmp/aveline/config.toml" <<EOF
api_url = "$E2E_API_URL"
token   = "avl_obviously_not_a_real_token_xxxxx"
EOF
  LAST_OUT="$(mktemp)"; LAST_ERR="$(mktemp)"
  XDG_CONFIG_HOME="$tmp" "$E2E_BIN" whoami >"$LAST_OUT" 2>"$LAST_ERR"
  LAST_EXIT=$?
  LAST_OUT_TEXT="$(cat "$LAST_OUT")"; LAST_ERR_TEXT="$(cat "$LAST_ERR")"
  rm -rf "$tmp"
  if [[ "$LAST_EXIT" == "3" ]]; then
    pass "unauthorized exits 3"
  else
    fail "unauthorized exit was $LAST_EXIT (expected 3)"
  fi
}

test_exit_code_4_for_not_found() {
  local ws; ws="$(mk_workspace ws-exit4)"
  run_cli -w "$ws" get-doc "ghost-$(us)"
  expect_exit 4 "not_found exits 4"
}

test_exit_code_0_for_success() {
  local ws; ws="$(mk_workspace ws-exit0)"
  run_cli -w "$ws" list-docs
  expect_exit 0 "success exits 0"
}

test_envelope_error_goes_to_stderr_not_stdout() {
  run_cli -w "ghost-$(us)" list-docs
  if [[ -z "$LAST_OUT_TEXT" ]]; then
    pass "error: stdout is empty"
  else
    fail "error: stdout had content (should be empty): $LAST_OUT_TEXT"
  fi
  if [[ -n "$LAST_ERR_TEXT" ]]; then
    pass "error: stderr has content"
  else
    fail "error: stderr empty"
  fi
}

test_envelope_success_goes_to_stdout_not_stderr() {
  local ws; ws="$(mk_workspace ws-env-streams)"
  run_cli -w "$ws" list-docs
  if [[ -n "$LAST_OUT_TEXT" ]]; then
    pass "success: stdout has content"
  else
    fail "success: stdout empty"
  fi
  if [[ -z "$LAST_ERR_TEXT" ]]; then
    pass "success: stderr is empty"
  else
    fail "success: stderr leaked: $LAST_ERR_TEXT"
  fi
}
