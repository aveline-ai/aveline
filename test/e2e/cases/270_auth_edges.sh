# shellcheck shell=bash
# Auth header parsing + token edge cases.

test_token_with_lowercase_bearer_accepted() {
  # API accepts both "Bearer" and "bearer". The CLI uses "Bearer", but
  # let's verify the server-side flexibility via curl.
  local out
  out="$(curl -s -H "Authorization: bearer $E2E_TOKEN_ALICE" "$E2E_API_URL/api/me")"
  if jq -e '.ok == true' <<<"$out" >/dev/null 2>&1; then
    pass "lowercase 'bearer' prefix accepted"
  else
    fail "lowercase 'bearer' rejected"
  fi
}

test_revoked_token_rejected() {
  # We can't actually revoke a token via the API, but we can validate
  # the unauthorized path with a malformed token.
  local out
  out="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer avl_revoked_xxxxxxxxxxxxxxxxxxxxxx" \
    "$E2E_API_URL/api/me")"
  if [[ "$out" == "401" ]]; then
    pass "unknown token returns 401"
  else
    fail "unknown token HTTP $out (expected 401)"
  fi
}

test_no_auth_header_returns_401() {
  local out
  out="$(curl -s -o /dev/null -w '%{http_code}' "$E2E_API_URL/api/me")"
  if [[ "$out" == "401" ]]; then
    pass "no auth → 401"
  else
    fail "no auth HTTP $out (expected 401)"
  fi
}

test_authorization_header_wrong_scheme_returns_401() {
  local out
  out="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Basic $E2E_TOKEN_ALICE" "$E2E_API_URL/api/me")"
  if [[ "$out" == "401" ]]; then
    pass "Basic scheme → 401"
  else
    fail "Basic scheme HTTP $out (expected 401)"
  fi
}

test_heartbeat_returns_service_name() {
  run_cli heartbeat
  expect_ok "heartbeat ok"
  local svc; svc="$(jq -r '.service' <<<"$LAST_OUT_TEXT")"
  if [[ -n "$svc" && "$svc" != "null" ]]; then
    pass "heartbeat service: $svc"
  else
    fail "heartbeat missing .service"
  fi
}

test_whoami_includes_workspaces_list() {
  run_cli whoami
  expect_ok "whoami ok"
  expect_present ".workspaces" "workspaces array surfaced"
  if jq -e '.workspaces | type == "array"' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "workspaces is an array"
  else
    fail "workspaces not an array"
  fi
}
