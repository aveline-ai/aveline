# shellcheck shell=bash
# Block types — every supported shape round-trips through create-doc +
# get-doc. Catches schema drift in the block validator.

# Emit a minimal block of a given type as JSON.
_b_heading_l1()   { jq -nc '{type:"heading", level:1, text:"Top"}'; }
_b_heading_l3()   { jq -nc '{type:"heading", level:3, text:"Deeper"}'; }
_b_paragraph()    { jq -nc '{type:"paragraph", content:[{text:"plain"}]}'; }
_b_paragraph_marked() {
  jq -nc '{type:"paragraph", content:[
    {text:"Bold ", marks:["bold"]},
    {text:"italic ", marks:["italic"]},
    {text:"code ", marks:["code"]},
    {text:"strike", marks:["strike"]}
  ]}'
}
_b_paragraph_link() {
  jq -nc '{type:"paragraph", content:[
    {text:"See "}, {text:"docs", marks:["bold"], link:{href:"https://example.com"}}, {text:"."}
  ]}'
}
_b_code_with_lang() {
  jq -nc '{type:"code", language:"elixir", content:"defmodule X do\nend"}'
}
_b_code_no_lang() {
  jq -nc '{type:"code", language:null, content:"plain code"}'
}
_b_list_unordered() {
  jq -nc '{type:"list", ordered:false, items:[
    {content:[{text:"first"}]},
    {content:[{text:"second"}]}
  ]}'
}
_b_list_ordered() {
  jq -nc '{type:"list", ordered:true, items:[
    {content:[{text:"step 1"}]},
    {content:[{text:"step 2"}]}
  ]}'
}

test_block_heading_l1_round_trips() {
  local ws; ws="$(mk_workspace ws-b-h1)"
  local blocks; blocks="[$(_b_heading_l1)]"
  run_cli -w "$ws" create-doc --title "H1" --blocks "$blocks"
  expect_ok "create heading L1 doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].type" "heading" "type is heading"
  expect_eq ".doc.blocks[0].level" "1" "level is 1"
  expect_eq ".doc.blocks[0].text" "Top" "text round-trips"
}

test_block_heading_l3_round_trips() {
  local ws; ws="$(mk_workspace ws-b-h3)"
  local blocks; blocks="[$(_b_heading_l3)]"
  run_cli -w "$ws" create-doc --title "H3" --blocks "$blocks"
  expect_ok "create heading L3 doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].level" "3" "level is 3"
}

test_block_paragraph_marks_round_trip() {
  local ws; ws="$(mk_workspace ws-b-marks)"
  local blocks; blocks="[$(_b_paragraph_marked)]"
  run_cli -w "$ws" create-doc --title "Marks" --blocks "$blocks"
  expect_ok "create marked paragraph"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_ok "get back marked doc"
  if jq -e '.doc.blocks[0].content | map(.marks // []) | flatten | (index("bold") and index("italic") and index("code") and index("strike"))' \
       <<<"$LAST_OUT_TEXT" >/dev/null 2>&1; then
    pass "all four marks preserved"
  else
    fail "some marks lost"
  fi
}

test_block_paragraph_link_round_trips() {
  local ws; ws="$(mk_workspace ws-b-link)"
  local blocks; blocks="[$(_b_paragraph_link)]"
  run_cli -w "$ws" create-doc --title "Link" --blocks "$blocks"
  expect_ok "create link paragraph"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq '.doc.blocks[0].content[1].link.href' "https://example.com" "link href preserved"
}

test_block_code_with_language() {
  local ws; ws="$(mk_workspace ws-b-code)"
  local blocks; blocks="[$(_b_code_with_lang)]"
  run_cli -w "$ws" create-doc --title "Code" --blocks "$blocks"
  expect_ok "create code-with-lang doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].language" "elixir" "language preserved"
  expect_eq ".doc.blocks[0].type" "code" "type is code"
}

test_block_code_without_language() {
  local ws; ws="$(mk_workspace ws-b-cnl)"
  local blocks; blocks="[$(_b_code_no_lang)]"
  run_cli -w "$ws" create-doc --title "Plain code" --blocks "$blocks"
  expect_ok "create code-no-lang doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].language" "null" "no-language stays null"
}

test_block_list_unordered() {
  local ws; ws="$(mk_workspace ws-b-lu)"
  local blocks; blocks="[$(_b_list_unordered)]"
  run_cli -w "$ws" create-doc --title "UL" --blocks "$blocks"
  expect_ok "create unordered list doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].ordered" "false" "unordered list"
  expect_count ".doc.blocks[0].items" "2" "two items"
}

test_block_list_ordered() {
  local ws; ws="$(mk_workspace ws-b-lo)"
  local blocks; blocks="[$(_b_list_ordered)]"
  run_cli -w "$ws" create-doc --title "OL" --blocks "$blocks"
  expect_ok "create ordered list doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].ordered" "true" "ordered list"
}

test_block_mixed_types_in_one_doc() {
  local ws; ws="$(mk_workspace ws-b-mix)"
  local blocks; blocks="[$(_b_heading_l1),$(_b_paragraph),$(_b_code_with_lang),$(_b_list_unordered)]"
  run_cli -w "$ws" create-doc --title "Mixed" --blocks "$blocks"
  expect_ok "create mixed-types doc"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_count ".doc.blocks" "4" "four blocks survive"
  expect_eq '.doc.blocks[0].type' "heading"   "block 0 heading"
  expect_eq '.doc.blocks[1].type' "paragraph" "block 1 paragraph"
  expect_eq '.doc.blocks[2].type' "code"      "block 2 code"
  expect_eq '.doc.blocks[3].type' "list"      "block 3 list"
}

test_block_unknown_type_rejected() {
  local ws; ws="$(mk_workspace ws-b-bad)"
  local blocks; blocks='[{"type":"frog","content":[{"text":"ribbit"}]}]'
  run_cli -w "$ws" create-doc --title "Frog" --blocks "$blocks"
  expect_exit 2 "unknown block type → validation_failed"
}

test_block_invalid_heading_level_rejected() {
  local ws; ws="$(mk_workspace ws-b-bh)"
  local blocks; blocks='[{"type":"heading","level":42,"text":"way too deep"}]'
  run_cli -w "$ws" create-doc --title "Deep" --blocks "$blocks"
  expect_exit 2 "heading level out of range → validation_failed"
}

test_block_ids_minted_when_absent() {
  local ws; ws="$(mk_workspace ws-b-ids)"
  local blocks; blocks="[$(_b_paragraph)]"
  run_cli -w "$ws" create-doc --title "Mint" --blocks "$blocks"
  expect_ok "create without ids"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_present ".doc.blocks[0].id" "block id minted server-side"
}

test_block_ids_respected_when_provided() {
  local ws; ws="$(mk_workspace ws-b-myid)"
  local blocks; blocks='[{"type":"paragraph","id":"b_my_chosen_id_here_22","content":[{"text":"x"}]}]'
  run_cli -w "$ws" create-doc --title "MyID" --blocks "$blocks"
  expect_ok "create with explicit valid id"
  local slug; slug="$(jq -r '.slug' <<<"$LAST_OUT_TEXT")"
  run_cli -w "$ws" get-doc "$slug"
  expect_eq ".doc.blocks[0].id" "b_my_chosen_id_here_22" "supplied id preserved"
}
