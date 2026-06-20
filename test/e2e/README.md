# End-to-end test suite

Real-HTTP smoke + contract suite that drives the **`aveline` CLI binary**
against a locally-booted Phoenix server. Because every assertion goes
through the CLI, a green run means *the API + envelope + CLI parsing +
exit codes all agree* — the same surface Claude will hit in production.

## Run

```sh
./test/e2e/run.sh                  # all cases
./test/e2e/run.sh 060_             # only files matching glob
./test/e2e/run.sh -k disposition   # only test functions whose name matches
```

Requirements: `bash` 4+, `jq`, `mix`, `go`, a reachable Postgres.

## What it does

1. Builds the CLI from `../cli` into `../cli/bin/aveline-e2e`.
2. Resets a dedicated `aveline_e2e` Postgres DB and runs the seed task
   (your normal dev DB is **untouched**).
3. Pre-creates one CLI config per seeded persona (`alice` / `bob` /
   `carol`) under a temp `$XDG_CONFIG_HOME`.
4. Boots Phoenix on **port 4099** against the e2e DB.
5. Sources every `cases/*.sh` and runs every function named `test_*` it
   defines.
6. Prints pass / fail and exits non-zero if anything failed.

## Independence guarantee

Every `test_*` function creates its own workspace, tags, docs, and
comments via `mk_workspace` / `mk_tag` / `mk_doc` / `mk_comment`. No test
reads from the seed and no test relies on another test's output, so the
whole suite could in principle run in parallel.

The seed exists only to provide three known users + bearer tokens; tests
mutate state only inside workspaces they own.

## File naming

Files use a 3-digit prefix because we'll likely cross 100 tests. Pick
the next free decade; cases inside a file should share a theme.

## Case map

| File | Theme | What it covers |
|------|-------|----------------|
| [`000_heartbeat.sh`](cases/000_heartbeat.sh) | Heartbeat | `heartbeat` happy path, no-auth, `--human` |
| [`010_auth.sh`](cases/010_auth.sh) | Auth | `whoami`, login token validation, env var, persisted config, `logout` |
| [`020_workspaces.sh`](cases/020_workspaces.sh) | Workspaces | list/get/create (slug rules + dup), `use-workspace` persist, `-w` override |
| [`030_docs_list.sh`](cases/030_docs_list.sh) | `list-docs` | empty, populated, `--pinned`, `--tag` (single + intersection), unknown tag, non-member |
| [`040_docs_get.sh`](cases/040_docs_get.sh) | `get-doc` | full body, block shape, version pointer, pin/tags echo, `not_found`, `workspace_not_found` |
| [`050_docs_create.sh`](cases/050_docs_create.sh) | `create-doc` | minimal, explicit slug, summary, tags, pin, dup, validation, `--blocks` from file/stdin/inline, invalid JSON |
| [`060_docs_apply_ops.sh`](cases/060_docs_apply_ops.sh) | `apply-ops` | all 5 ops, version bumps, every disposition action + every disposition error code, title/unpin via apply-ops, `not_found` |
| [`070_docs_lifecycle.sh`](cases/070_docs_lifecycle.sh) | Doc lifecycle | delete → restore → kudos (incl. `self_kudos`, `not_user_deleted`, double-delete) |
| [`080_versions.sh`](cases/080_versions.sh) | Versions | `list-versions` v1-only, v2 after apply-ops, `get-version` snapshots, `not_found` |
| [`090_comments.sh`](cases/090_comments.sh) | Comments | create (doc-level + block), reply thread, edit/delete (author-only `forbidden`), undelete, resolve/unresolve, missing body |
| [`100_tags.sh`](cases/100_tags.sh) | Tags | CRUD, dup, invalid slug, rename, description, `would_orphan_docs` |
| [`110_team.sh`](cases/110_team.sh) | Team + invites | list/add/remove, `already_member`, `self_remove`, `not_member`, invite idempotent, revoke + new code |
| [`120_events.sh`](cases/120_events.sh) | Events | empty, records doc creation, `--limit`, `--before-id` pagination |
| [`130_envelope.sh`](cases/130_envelope.sh) | Envelope contract | `ok:true` flat / `ok:false` nested, error code+message, exit 0/2/3/4, stdout vs stderr |
| [`140_cli_contract.sh`](cases/140_cli_contract.sh) | CLI contract | JSON default, `--human` pretty, `--api-url` + `-w` overrides, unknown verb, root + per-verb `--help` |
| [`150_blocks_types.sh`](cases/150_blocks_types.sh) | Block schema round-trip | every block type (heading L1/L3, paragraph, code w/ + w/o language, list ordered/unordered), marks (bold/italic/code/strike), links, mixed-type doc, unknown type rejection, id-mint vs provided |
| [`160_dispositions_happy.sh`](cases/160_dispositions_happy.sh) | Disposition happy paths | resolve+reply round-trips, reanchor keeps thread open, leave note, mixed in single apply-ops, resolve without reply rejected, untouched block needs no disposition |
| [`170_comments_deeper.sh`](cases/170_comments_deeper.sh) | Comments deeper | 3-deep threads, edit bumps version_number, undelete restores, reply inherits parent's block anchor, delete doc hides its comments, empty body rejected |
| [`180_input_forms.sh`](cases/180_input_forms.sh) | Input forms | `--blocks` inline = file = stdin, `--ops` file = stdin, `--body` @file/stdin, `--dispositions` from file, invalid JSON file rejected |
| [`190_combo_filters.sh`](cases/190_combo_filters.sh) | Combined filters + pagination | `--pinned --tag X` together, limit=N caps results, before-id advances, no-filter excludes deleted, `--pinned=false`, limit=0 falls back |
| [`200_unicode.sh`](cases/200_unicode.sh) | Unicode + edge chars | emoji titles, multi-byte in code blocks, apostrophes, max-length summary, over-limit summary rejected, quotes in comment bodies |
| [`210_kudos_ownership.sh`](cases/210_kudos_ownership.sh) | Kudos + ownership | toggle on/off, multi-user accumulates, self-kudos blocked even post-edit, kudos on deleted doc errors, owner persists across edits |
| [`220_time_travel.sh`](cases/220_time_travel.sh) | Version snapshots | v1/v2 snapshots accurate, intent preserved per version, list-versions chronological count, missing version → not_found |
| [`230_isolation.sh`](cases/230_isolation.sh) | Workspace isolation | non-member denied (list/get/create/comment/tags/events), workspace-list scoped, no leak across workspaces, added member can access |
| [`240_tag_cascade.sh`](cases/240_tag_cascade.sh) | Tag cascades | rename cascades into doc.tags, delete unused tag, delete blocked when only tag, succeeds after retag, unknown tag rejected |
| [`250_apply_ops_metadata.sh`](cases/250_apply_ops_metadata.sh) | Metadata via apply-ops | title/summary/tags/pin update in-place, missing metadata preserves prior values, intent attached to new version |
| [`260_scale.sh`](cases/260_scale.sh) | Scale | 30-block doc, 10 versions, 15 comments, 25 docs, 10 ops in one call |
| [`270_auth_edges.sh`](cases/270_auth_edges.sh) | Auth header edges | lowercase `bearer` accepted, unknown token → 401, missing header → 401, wrong scheme → 401, heartbeat fields, whoami workspaces array |
| [`280_list_ordering.sh`](cases/280_list_ordering.sh) | List ordering | docs pinned-first, recent-first among unpinned, versions newest-first, events newest-first, tags include doc_count |

> Total cases: **481** as of this commit. Add to this table whenever you
> add a case file — the table is the source of truth for what we believe
> we've covered.

## Writing a new case

Drop a new function called `test_<thing>` into the appropriate file (or
make a new `NNN_topic.sh`). The runner picks it up automatically.

The case helpers ([`lib.sh`](lib.sh)) give you:

| Helper | Purpose |
|--------|---------|
| `run_cli <args…>` | Run `aveline <args>` as the current persona. Stores `$LAST_OUT_TEXT`, `$LAST_ERR_TEXT`, `$LAST_EXIT`. |
| `as_persona <p> <args…>` | One-shot run as `bob` / `carol` without affecting the default. |
| `mk_workspace [label]` | Echo a fresh workspace slug owned by alice. |
| `mk_tag <ws> <name>` | Create + echo a tag in `<ws>`. |
| `mk_doc <ws> [title] [tag1,tag2]` | Create + echo a doc slug with sensible defaults. |
| `mk_comment <ws> <doc> <body>` | Create + echo a top-level comment id. |
| `add_member <ws> <username>` | Idempotently add a seeded user. |
| `block_paragraph <text>` / `block_heading <level> <text>` | Emit a valid block JSON literal. |
| `us <prefix>` | Generate a collision-resistant slug suffix. |

Assertion helpers (each increments pass/fail):

| Helper | Purpose |
|--------|---------|
| `expect_ok <msg>` | exit 0 AND `.ok == true` on stdout |
| `expect_err <code> <exit> <msg>` | non-zero exit, code matches, error envelope on stderr |
| `expect_exit <code> <msg>` | exact exit code |
| `expect_eq <jq-path> <want> <msg>` | jq -r path equals string |
| `expect_present <jq-path> <msg>` | jq path resolves to non-null, non-empty |
| `expect_absent <jq-path> <msg>` | jq path is null or missing |
| `expect_count <jq-array-path> <n> <msg>` | array length equals n |
| `pass <msg>` / `fail <msg>` | use directly for custom assertions |

## Adding tests for a new endpoint

1. Pick a free file prefix (`NNN_endpoint.sh`).
2. Write `test_*` functions. Each one creates its own workspace.
3. Add a row to the **Case map** table above.
4. Run `./test/e2e/run.sh NNN_` to focus on just that file while you
   develop.

## Notes / known gotchas

- The runner refuses to start if port 4099 is busy. Pass
  `E2E_PORT=<free port>` if you need to relocate.
- The seed is **destructive** to the `aveline_e2e` DB — never to
  `aveline_dev`.
- `.server.log` and `.seed.log` are written next to `run.sh` for
  debugging; both are gitignored.
- The CLI is rebuilt every run. It's fast (~1s) and means you never
  e2e-test stale code.
