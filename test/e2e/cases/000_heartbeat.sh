# shellcheck shell=bash
# Heartbeat — the only unauthenticated endpoint. If this fails, nothing
# else will pass.

test_heartbeat_ok() {
  run_cli heartbeat
  expect_ok "heartbeat returns ok envelope"
  expect_present ".service" "service name present"
  expect_present ".version" "version present"
}

test_heartbeat_works_without_token() {
  # Strip the token from config; heartbeat should still work.
  local saved="$E2E_TOKEN_ALICE"
  AVELINE_E2E_TOKEN="not-a-real-token-and-its-ignored-anyway"
  run_cli heartbeat
  expect_ok "heartbeat ignores bogus token"
  AVELINE_E2E_TOKEN="$saved"
}

test_heartbeat_human_mode() {
  run_cli --human heartbeat
  expect_exit 0 "human heartbeat exits 0"
  # --human pretty-prints — should still parse as JSON
  echo "$LAST_OUT_TEXT" | jq -e . >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then pass "human output is still valid JSON"; else fail "human output not valid JSON"; fi
}
