# shellcheck shell=bash
# Workspaces — list, get, create, use. Every test creates its own
# workspace; no test depends on the seed.

test_workspaces_list_includes_my_new_workspace() {
  local slug; slug="$(mk_workspace ws-in-list)"
  run_cli list-workspaces
  expect_ok "list-workspaces ok"
  if jq -e --arg s "$slug" '.workspaces | map(.slug) | index($s)' <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "list includes just-created workspace"
  else
    fail "just-created workspace missing from list"
  fi
}

test_workspaces_get_returns_metadata() {
  local slug; slug="$(mk_workspace ws-get)"
  run_cli get-workspace "$slug"
  expect_ok "get-workspace ok"
  expect_eq ".workspace.slug" "$slug" "slug matches"
  expect_present ".workspace.name" "name present"
}

test_workspaces_get_not_found() {
  run_cli get-workspace "ghost-$(us nope)"
  expect_err "workspace_not_found" 4 "missing workspace → workspace_not_found"
}

test_workspaces_create_with_explicit_slug() {
  local slug; slug="$(us explicit-ws)"
  run_cli create-workspace --name "Explicit" --slug "$slug"
  expect_ok "create-workspace with explicit slug"
  expect_eq ".workspace.slug" "$slug" "echoed slug matches"
}

test_workspaces_create_auto_slug_from_name() {
  run_cli create-workspace --name "Auto Slug $(us)"
  expect_ok "create-workspace derives slug from name"
  expect_present ".workspace.slug" "derived slug present"
}

test_workspaces_create_duplicate_slug() {
  local slug; slug="$(us dup-ws)"
  run_cli create-workspace --name "First" --slug "$slug"
  expect_ok "first create ok"
  run_cli create-workspace --name "Second" --slug "$slug"
  expect_err "slug_taken" 2 "duplicate slug → slug_taken / exit 2"
}

test_workspaces_create_no_name_local_error() {
  run_cli create-workspace
  if [[ "$LAST_EXIT" != "0" ]]; then
    pass "create-workspace without --name exits non-zero"
  else
    fail "create-workspace accepted empty --name"
  fi
}

test_workspaces_use_writes_to_config() {
  local tmp; tmp="$(mktemp -d)"; mkdir -p "$tmp/aveline"
  cat > "$tmp/aveline/config.toml" <<EOF
api_url = "$E2E_API_URL"
token   = "$E2E_TOKEN_ALICE"
EOF
  local slug; slug="$(mk_workspace ws-use)"
  XDG_CONFIG_HOME="$tmp" "$E2E_BIN" use-workspace "$slug" >/dev/null
  if grep -q "workspace = \"$slug\"" "$tmp/aveline/config.toml"; then
    pass "use-workspace persisted slug"
  else
    fail "use-workspace did not write slug"
  fi
  rm -rf "$tmp"
}

test_workspaces_w_flag_overrides_default() {
  local slug; slug="$(mk_workspace ws-flag)"
  # Switch default persona has no workspace set; -w should pick this one.
  run_cli -w "$slug" list-docs
  expect_ok "-w override targets the new workspace"
  expect_count "$MY_DOCS" "0" "fresh workspace has only the seeded orientation doc"
}

test_workspaces_create_then_immediately_usable() {
  local slug; slug="$(mk_workspace ws-roundtrip)"
  run_cli -w "$slug" list-tags
  expect_ok "list-tags on brand-new workspace ok"
  expect_count ".tags" "20" "brand-new workspace has the template tags"
}
