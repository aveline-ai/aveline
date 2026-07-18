# shellcheck shell=bash
# list-docs as the query surface — full-text search, snippets, limits.

test_search_filters_and_snippets() {
  local ws; ws="$(mk_workspace ws-fts-basic)"
  mk_doc "$ws" "Kraken deploy notes" >/dev/null
  mk_doc "$ws" "Unrelated gardening" >/dev/null

  run_cli -w "$ws" list-docs --q "kraken"
  expect_ok "search ok"
  expect_count "$MY_DOCS" "1" "only the matching doc"
  expect_eq "$MY_DOCS | .[0].title" "Kraken deploy notes" "right doc"
  if jq -e "$MY_DOCS | .[0].snippet | contains(\"**\")" <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "hit carries a marked snippet"
  else
    fail "snippet missing or unmarked: $(jq -c "$MY_DOCS | .[0].snippet" <<<"$LAST_OUT_TEXT")"
  fi
}

test_search_excludes_with_minus() {
  local ws; ws="$(mk_workspace ws-fts-minus)"
  mk_doc "$ws" "Postgres tuning" >/dev/null
  mk_doc "$ws" "Postgres backups" >/dev/null

  run_cli -w "$ws" list-docs --q "postgres -backups"
  expect_ok "exclusion search ok"
  expect_count "$MY_DOCS" "1" "one doc after exclusion"
  expect_eq "$MY_DOCS | .[0].title" "Postgres tuning" "excluded doc gone"
}

test_no_query_no_snippet() {
  local ws; ws="$(mk_workspace ws-fts-nosnip)"
  mk_doc "$ws" "Plain doc" >/dev/null

  run_cli -w "$ws" list-docs
  if jq -e "$MY_DOCS | .[0] | has(\"snippet\") | not" <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "no snippet key without --q"
  else
    fail "snippet key present without a query"
  fi
}

test_limit_and_offset_page() {
  local ws; ws="$(mk_workspace ws-fts-page)"
  mk_doc "$ws" "Pager one" >/dev/null
  mk_doc "$ws" "Pager two" >/dev/null
  mk_doc "$ws" "Pager three" >/dev/null

  run_cli -w "$ws" list-docs --q "pager" --limit 2
  expect_count "$MY_DOCS" "2" "limit caps results"

  run_cli -w "$ws" list-docs --q "pager" --limit 2 --offset 2
  expect_count "$MY_DOCS" "1" "offset reaches the last page"
}

test_bad_params_are_machine_readable() {
  local ws; ws="$(mk_workspace ws-fts-errs)"

  run_cli -w "$ws" list-docs --sort bogus
  expect_err "list_param_invalid" 2 "bad sort → list_param_invalid"

  run_cli -w "$ws" list-docs --limit 500
  expect_err "list_param_invalid" 2 "oversized limit → list_param_invalid"

  run_cli -w "$ws" list-docs --author user-that-does-not-exist
  expect_err "unknown_authors" 2 "unknown author → unknown_authors"
}
