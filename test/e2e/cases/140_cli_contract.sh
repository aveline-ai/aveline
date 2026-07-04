# shellcheck shell=bash
# CLI contract — JSON-default, --human pretty, flag overrides, exit codes.

test_json_is_default_output() {
  local ws; ws="$(mk_workspace ws-cc-json)"
  run_cli -w "$ws" list-docs
  # Output should be parseable as a single-line JSON.
  if echo "$LAST_OUT_TEXT" | jq -e . >/dev/null 2>&1; then
    pass "default output is valid JSON"
  else
    fail "default output not JSON"
  fi
}

test_human_flag_still_valid_json() {
  local ws; ws="$(mk_workspace ws-cc-hum)"
  run_cli -w "$ws" --human list-docs
  if echo "$LAST_OUT_TEXT" | jq -e . >/dev/null 2>&1; then
    pass "--human output is still valid JSON"
  else
    fail "--human output not valid JSON"
  fi
}

test_human_flag_pretty_prints() {
  local ws; ws="$(mk_workspace ws-cc-prty)"
  run_cli -w "$ws" --human list-docs
  # Pretty-printed JSON is multi-line.
  local nlines; nlines="$(echo "$LAST_OUT_TEXT" | wc -l | tr -d ' ')"
  if [[ "$nlines" -gt 1 ]]; then
    pass "--human is multi-line (pretty)"
  else
    fail "--human is single-line, not pretty"
  fi
}

test_api_url_flag_overrides() {
  local ws; ws="$(mk_workspace ws-cc-url)"
  # Point at a deliberately wrong URL; should fail to connect.
  run_cli --api-url "http://127.0.0.1:1" -w "$ws" list-docs
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "--api-url override took effect (errored on bad URL)"
  else
    fail "--api-url override ignored"
  fi
}

test_w_flag_overrides_config_workspace() {
  # Two workspaces; default config has none — switch via -w.
  local a; a="$(mk_workspace ws-cc-flagA)"
  local b; b="$(mk_workspace ws-cc-flagB)"
  mk_doc "$a" "InA" >/dev/null
  run_cli -w "$b" list-docs
  expect_ok "list ws B"
  expect_count "$MY_DOCS" "0" "ws B is empty (-w isolated)"
  run_cli -w "$a" list-docs
  expect_ok "list ws A"
  expect_count "$MY_DOCS" "1" "ws A has the doc"
}

test_unknown_verb_local_error() {
  run_cli not-a-real-verb 2>/dev/null
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "unknown verb exits non-zero"
  else
    fail "unknown verb accepted"
  fi
}

test_help_lists_every_verb() {
  XDG_CONFIG_HOME="$(persona_xdg)" "$E2E_BIN" --help > "$(mktemp /tmp/aveline-help-XXXX)" 2>&1
  local helptxt; helptxt="$(XDG_CONFIG_HOME="$(persona_xdg)" "$E2E_BIN" --help 2>&1)"
  # Spot-check verbs from every category.
  local missing=0
  for v in list-docs create-doc apply-ops list-comments create-tag list-members get-invite list-events heartbeat whoami; do
    if ! grep -q "$v" <<<"$helptxt"; then
      missing=$((missing + 1))
      fail "help missing $v"
    fi
  done
  if [[ "$missing" -eq 0 ]]; then pass "help lists every spot-checked verb"; fi
}

test_per_verb_help_renders() {
  for v in create-doc apply-ops create-comment edit-tag list-events; do
    local out
    out="$(XDG_CONFIG_HOME="$(persona_xdg)" "$E2E_BIN" "$v" --help 2>&1)"
    if [[ -n "$out" ]] && grep -q "Usage:" <<<"$out"; then
      pass "$v --help renders"
    else
      fail "$v --help empty or malformed"
    fi
  done
}
