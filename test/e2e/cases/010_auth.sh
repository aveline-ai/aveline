# shellcheck shell=bash
# Auth — token validation, login/logout, whoami.

# Run the CLI inside an isolated tmp XDG dir. Captures stdout/stderr/exit
# the same way run_cli does. Useful for auth tests that need to control
# the config from scratch.
#
# Usage: _isolated_cli <tmp_dir> <args…>
_isolated_cli() {
  local tmp="$1"; shift
  LAST_OUT="$(mktemp)"; LAST_ERR="$(mktemp)"
  XDG_CONFIG_HOME="$tmp" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" "$@" >"$LAST_OUT" 2>"$LAST_ERR"
  LAST_EXIT=$?
  LAST_OUT_TEXT="$(cat "$LAST_OUT")"
  LAST_ERR_TEXT="$(cat "$LAST_ERR")"
}

# Write an empty (no token) config inside <tmp>
_write_empty_config() {
  local tmp="$1"
  mkdir -p "$tmp/aveline"
  cat > "$tmp/aveline/config.toml" <<EOF
api_url = "$E2E_API_URL"
EOF
}

test_whoami_returns_user() {
  run_cli whoami
  expect_ok "whoami ok"
  expect_eq ".user.username" "alice" "whoami returns alice"
  expect_present ".user.email" "user email present"
}

test_whoami_with_bogus_token_unauthorized() {
  local tmp; tmp="$(mktemp -d)"; mkdir -p "$tmp/aveline"
  cat > "$tmp/aveline/config.toml" <<EOF
api_url = "$E2E_API_URL"
token   = "avl_obviously_not_a_real_token_xxxxx"
EOF
  _isolated_cli "$tmp" whoami
  expect_err "unauthorized" 3 "bogus token → unauthorized"
  rm -rf "$tmp"
}

test_whoami_no_token_local_error() {
  local tmp; tmp="$(mktemp -d)"
  _write_empty_config "$tmp"
  _isolated_cli "$tmp" whoami
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "no-token whoami exits non-zero (got $LAST_EXIT)"
  else
    fail "no-token whoami unexpectedly succeeded"
  fi
  rm -rf "$tmp"
}

test_login_rejects_non_avl_prefix() {
  local tmp; tmp="$(mktemp -d)"
  _isolated_cli "$tmp" login --token "not_an_avl_token"
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "login rejects token without avl_ prefix"
  else
    fail "login accepted non-avl_ token"
  fi
  rm -rf "$tmp"
}

test_login_persists_and_authenticates() {
  local tmp; tmp="$(mktemp -d)"
  _isolated_cli "$tmp" login --token "$E2E_TOKEN_BOB"
  expect_exit 0 "login as bob exits 0"
  if grep -q "$E2E_TOKEN_BOB" "$tmp/aveline/config.toml" 2>/dev/null; then
    pass "login persisted bob's token to config"
  else
    fail "login didn't write config"
    rm -rf "$tmp"; return
  fi
  _isolated_cli "$tmp" whoami
  expect_eq ".user.username" "bob" "whoami after login returns bob"
  rm -rf "$tmp"
}

test_logout_clears_token() {
  local tmp; tmp="$(mktemp -d)"; mkdir -p "$tmp/aveline"
  cat > "$tmp/aveline/config.toml" <<EOF
api_url   = "$E2E_API_URL"
token     = "$E2E_TOKEN_ALICE"
workspace = "$E2E_WORKSPACE"
EOF
  _isolated_cli "$tmp" logout
  if ! grep -q "avl_" "$tmp/aveline/config.toml"; then
    pass "logout removed token from config"
  else
    fail "logout did not remove token"
  fi
  if grep -q "workspace" "$tmp/aveline/config.toml"; then
    pass "logout preserved workspace setting"
  else
    fail "logout wiped workspace"
  fi
  rm -rf "$tmp"
}

test_login_reads_avl_token_env() {
  local tmp; tmp="$(mktemp -d)"
  LAST_OUT="$(mktemp)"; LAST_ERR="$(mktemp)"
  AVELINE_TOKEN="$E2E_TOKEN_CAROL" \
    XDG_CONFIG_HOME="$tmp" AVELINE_API_URL="$E2E_API_URL" \
    "$E2E_BIN" login >"$LAST_OUT" 2>"$LAST_ERR"
  LAST_EXIT=$?
  if [[ "$LAST_EXIT" == "0" ]] && grep -q "$E2E_TOKEN_CAROL" "$tmp/aveline/config.toml" 2>/dev/null; then
    pass "login reads AVELINE_TOKEN env"
  else
    fail "login didn't pick up AVELINE_TOKEN env (exit=$LAST_EXIT)"
  fi
  rm -rf "$tmp"
}
