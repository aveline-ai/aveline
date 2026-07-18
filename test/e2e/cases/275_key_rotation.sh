# shellcheck shell=bash
# API key self-service — list masked, mint (plaintext once), guarded
# revoke. Only spare keys created here are revoked; the persona's login
# key is never touched (other cases share it).

test_list_keys_masked() {
  run_cli list-keys
  expect_ok "list-keys ok"
  if jq -e '.keys | length >= 1' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "at least the login key listed"
  else
    fail "expected at least one key"
  fi
  if jq -e '.keys[0].masked | test("…")' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "keys are masked"
  else
    fail "expected masked display"
  fi
  if grep -q "token_hash" <<<"$LAST_OUT_TEXT"; then
    fail "hash leaked in list payload"
  else
    pass "no hash in payload"
  fi
}

test_create_and_revoke_spare() {
  run_cli create-key --name "e2e-spare"
  expect_ok "create-key ok"
  local key id
  key="$(jq -r '.key' <<<"$LAST_OUT_TEXT")"
  id="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"
  if [[ "$key" == avl_* ]]; then
    pass "plaintext returned once at mint"
  else
    fail "expected avl_ plaintext in create response"
  fi
  expect_eq '.masked' "avl_…${key: -4}" "masked display is last 4"

  # The new key authenticates (throwaway config dir; login stores it).
  local tmpxdg; tmpxdg="$(mktemp -d -t aveline-e2e-keys.XXXXXX)"
  XDG_CONFIG_HOME="$tmpxdg" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" login --token "$key" >/dev/null 2>&1
  if XDG_CONFIG_HOME="$tmpxdg" AVELINE_API_URL="$E2E_API_URL" \
       "$E2E_BIN" whoami >/dev/null 2>&1; then
    pass "freshly minted key authenticates"
  else
    fail "new key failed to authenticate"
  fi

  run_cli list-keys
  if grep -q "$key" <<<"$LAST_OUT_TEXT"; then
    fail "plaintext key leaked in list"
  else
    pass "plaintext never listed again"
  fi

  run_cli revoke-key "$id"
  expect_ok "revoke-key ok"

  if XDG_CONFIG_HOME="$tmpxdg" AVELINE_API_URL="$E2E_API_URL" \
       "$E2E_BIN" whoami >/dev/null 2>&1; then
    fail "revoked key still authenticates"
  else
    pass "revoked key stops authenticating"
  fi
}

test_create_key_requires_name() {
  run_cli create-key --name "   "
  expect_err "validation_failed" 2 "blank name refused"
}

test_revoke_edge_cases() {
  # The last_key guard itself is covered by controller tests — exercising
  # it here would need a throwaway account (personas share their login
  # key across cases).
  run_cli create-key --name "e2e-guard"
  local key id
  key="$(jq -r '.key' <<<"$LAST_OUT_TEXT")"
  id="$(jq -r '.id' <<<"$LAST_OUT_TEXT")"

  # Revoking an id that isn't yours / doesn't exist: not_found.
  run_cli revoke-key "00000000-0000-0000-0000-000000000000"
  expect_err "not_found" 4 "unknown key id → not_found"

  # Clean up the spare so the persona ends exactly as it started.
  run_cli revoke-key "$id"
  expect_ok "spare cleaned up"
}
