# Aveline — Product & Design

> Notion, built for AI agents.

## What it is

Aveline is a shared knowledge layer for small engineering teams whose work
already runs through AI agents (Claude, etc.). Captured knowledge is read and
written by agents as a side effect of normal work, with provenance, ownership,
and decay built in — the things Notion/Confluence-style wikis have famously
failed at because humans don't maintain them.

The killer move isn't a better wiki UI. It's that **agents are the primary
writers and readers**, and a human-facing web UI is the secondary, inspection
surface.

## The wedge

**Solo Aveline**: Claude's working memory for you, persisted across sessions.
**Multi Aveline**: the same thing, shared with your pod.

Same data model, same mechanics, just N members vs 1. The system must be
*genuinely useful for one user* before pod features pile on. If the solo
loop isn't worth your daily attention, no number of teammates fixes that.

The realistic adoption path mirrors Notion's: personal use → team rollout.
You start using it alone. Once it earns trust, you invite a teammate to a
shared workspace. The pod features (mentions, threaded discussion, DRI
surface) become live; nothing about the model changes.

Two engineers (Arie + Trevor at Stable) currently share working context
through a github repo of markdown files plus custom Claude skills. That
workaround is the proof at the pod scale. The solo proof is even simpler:
your Claude already forgets useful things between sessions — Aveline is
where you persist them.

**Scope discipline**: build for the individual first, pod second. Resist
features that only matter at org/team-wide scale (notification infra,
multi-team UI, granular permissions, etc.) until v2+.

## How it works (mental model)

- **Workspaces** scope knowledge. Each workspace has members, items, and
  conversations.
- **Items** are markdown documents. They have an owner (a human), a status
  (`active | flagged | retired`), and a single behavior toggle: **`pinned`**.
- **Pinned items** are the curated "key context" auto-loaded into Claude's
  working memory when it attaches to a workspace. Unpinned items are
  searchable scratchpad — there but not noisy.
- **Item messages** are threaded replies under an item. Anyone in the
  workspace can reply. `@mentions` in body or message text create the
  "open ask" relationship.
- **Item versions** are append-only history of edits. Anyone in the workspace
  can edit any item (wiki-style); the owner has visibility and can revert.
- **Items, messages, and workspaces are all soft-deleted.** Destruction is
  recoverable, URLs stay live with a "deleted" banner.

The CLI (`stable`) is the primary surface for agents. The web UI (LiveView)
is for human browsing, thread replies, and "where things stand."

## Design principles

Four durable principles. Apply when designing schema, endpoints, or features.

### 0. Single-player must be valuable on its own

The system must be genuinely useful for one user before any pod features
become relevant. Multiplayer is *additive*, never load-bearing.

- A workspace with one member is a first-class use case, not a degenerate edge.
- Every mechanic (pin, flag, version, @mention, threads, soft-delete) must
  have a coherent meaning for a single user. `@self` is a ping-future-self
  pattern; threads-with-yourself are a journal/decision-log; the DRI surface
  is "your own items with edits over time."
- If a feature only earns its weight at N>1, it's deferred. Examples:
  workspace invites, notifications, multi-user permissions.

This frames the wedge (solo first, pod additively) and the v0 milestone
(use it alone for a week before any sharing).

### 1. Minimal hidden state

The database stores what users *did* (typed, clicked, set), not opaque
derived state. State that *can* be a query *should* be a query.

- `@mentions` live in text, not a side-table with `resolved_at`. "Open asks"
  is a query: latest `@X` vs latest message-by-X timestamp.
- "Expired" / "stale" are queries against `updated_at`, not stored states.
- Status enums encode explicit user actions only (`flagged`, `retired`),
  never derived facts (no `open` / `resolved` that drift from reality).

When tempted to add a column for derived state, ask: "could a query answer
this?" If yes, prefer the query. Denormalize only as cache, marked as such.

### 2. API-time validation

Invalid input rejected at the server boundary with a clear structured error
envelope. The CLI is a thin client that renders the server's errors.

- `@username` must resolve to a workspace member at save time, or the save
  fails with `{error: {code: "unknown_mention", ...}}`.
- Owner of an item must be in the workspace.
- Slug uniqueness, references must exist, etc.
- One error envelope shape for everything: `{error: {code, message, field, context}}`.

Don't duplicate validation in the CLI. The server is the source of truth;
the CLI just shows what comes back.

### 3. Soft-delete from day one

`deleted_at` + `deleted_by_id` on every user-facing table from the first
migration. Trivial on day one; multi-week migration to retrofit later.

- Default queries filter `WHERE deleted_at IS NULL` (context modules base
  every query off a `base_query/0` helper).
- Direct URL access still works for deleted items, with a "deleted" banner.
- Hard deletes only for membership/relationship rows and tokens.
- Cascade behavior is implicit through queries — deleting a workspace hides
  its items in default lists, but URLs still resolve.

## Data model

Eight tables for v0+ scope. UUID primary keys throughout.

```
users                      id, username, ...
teams                      id, name, slug
team_memberships           (team_id, user_id, role)
workspaces                 id, team_id, slug, name, deleted_at, ...
workspace_memberships      (workspace_id, user_id)
items                      id, workspace_id, slug, title, body, summary,
                           pinned (bool), status (active|flagged|retired),
                           owner_id, project_ref, tags[], sources[],
                           created_by_id, created_via,
                           flag_reason, flagged_by_id, flagged_at,
                           deleted_at, deleted_by_id,
                           inserted_at, updated_at
item_messages              id, item_id, author_id, body,
                           created_via, edited_at,
                           deleted_at, deleted_by_id,
                           inserted_at
item_versions              id, item_id, version_number, title, body,
                           summary, tags[], sources[],
                           edited_by_id, edited_via, edit_note,
                           inserted_at
api_tokens                 id, user_id, name, token_hash,
                           last_used_at, revoked_at
```

What's deliberately not modeled (v0):

- No `mentions` table — `@username` lives in text, "open asks" is a query
- No `is_question` field — replaced by the @-mention model
- No `projects` table — `project_ref` is a free-form string on items
- No `tags` table — `text[]` array on items
- No `notifications` table — surfaced via "open asks" + "mine" queries
- No `attachments` — markdown linking to external URLs is enough

## CLI verb surface

Operates against an active workspace. Token auth via `Authorization: Bearer`.

```
# auth + workspace selection
stable login
stable workspace use <slug>
stable workspace list

# items
stable list [--pinned]
stable get <slug>
stable save [--pin] --title "..." [--body -]
stable edit <slug> [-m "note"]
stable delete <slug>
stable restore <slug>

# versioning
stable history <slug>
stable diff <slug> <n>
stable revert <slug> <n>

# pinning / status
stable pin <id>
stable unpin <id>
stable resolve <id>
stable flag <id> --reason "..."

# threads
stable reply <id> [--body -]
stable edit-msg <id>
stable ack <id>
stable mention <id> @user

# discovery
stable asks               # @-mentions waiting for me
stable asks --mine        # @-mentions I've made
stable mine               # items I own (with recent edits highlighted)
```

The skill file (a markdown doc users drop in their Claude config) teaches
Claude which verbs to call when. Iteratable independently of the binary.

## Editorial model

The two interesting moments in the system are **pinning** and **flagging**.

- **Pin**: declares "this is key context, auto-load for Claude every session."
  Happens after writing, not at write time. The act of pinning *is* the
  editorial review that elevates working notes to durable knowledge.
- **Flag**: declares "this fact is wrong or stale." Anyone in the workspace
  can flag (including agents, after a fact turned out wrong in their use).
  Owner resolves: verify, update, or retire.

DRI lives in `owner_id` + the `stable mine` surface ("your items, edited by
others recently"). Not a PR-approval workflow — friction is reserved for
flags, not for every edit. Per-item `requires_edit_approval` flag is a
cheap future upgrade if specific items need stricter gating.

## Architecture

```
aveline.ai                Cloudflare Pages — static landing page
  www.aveline.ai            (alias)
app.aveline.ai            Fly.io — Phoenix backend (LiveView + JSON API)
  /                         LiveView UI (workspaces, items, threads)
  /api/*                    JSON API for CLI (bearer-token auth)
```

Two repos build the system:

- `aveline-ai/aveline` — this repo. Phoenix backend + LiveView UI. AGPL-3.0.
- `aveline-ai/cli` — Go CLI binary that talks to the API. MIT. *Not yet built.*
- `aveline-ai/landing` — static marketing page. No license.

LiveView is **same-origin** with the API. CLI hits `/api/*` from outside,
bearer-token authed. No CORS gymnastics, one Phoenix app.

## Why these choices

**Why LiveView and not a separate React client**: the UI is secondary
(agents are primary). Real-time threading + form-heavy surface is LV's
bullseye. Same-origin removes cookie/CSRF/CORS pain.

**Why AGPL backend, MIT CLI**: open source as a value, with optionality for
commercial dual-licensing later if enterprise demand materializes. AGPL
deters competitor-as-SaaS forks; MIT for client code is conventional.

**Why a graph isn't first-class**: the wedge doesn't need traversal queries;
a flat `items` table with tags + project refs covers v0–v2. Graph schemas
are expensive to evolve once data accumulates. Don't pick "graph" because
it sounds powerful — only when flat demonstrably fails.

**Why no auth UI for v0**: pre-PMF, two known users. Manual seed users +
share API tokens via 1Password. Build proper signup when a third pod adopts.

## Status

✅ Hello-world LiveView + counter + heartbeat endpoint deployed to app.aveline.ai
✅ Sentry wired end-to-end (Issues + Logs)
✅ Asset pipeline (esbuild, live reload), Phoenix 1.8, LiveView 1.0
✅ Repo open-sourced (AGPL-3.0), public, under aveline-ai org
✅ Landing page live at aveline.ai

🔲 Real schema: teams, workspaces, items, item_messages, item_versions, api_tokens
🔲 Bearer-token auth plug + first API endpoints
🔲 `aveline-ai/cli` repo (Go + cobra + goreleaser)
🔲 Skill file for Claude Code integration
🔲 LiveView pages: workspace list, item detail with thread
🔲 Manual user seed flow (psql + 1Password for v0)

## Stack notes

- Elixir 1.18+, Erlang/OTP 27+
- Phoenix 1.8, Phoenix LiveView 1.0, Bandit, Phoenix.PubSub
- PostgreSQL via Supabase (Session pooler — not direct, not transaction pooler)
- Oban (queues empty for v0; supervised, ready when needed)
- Sentry 12 with `enable_logs: true` (Logger → Sentry Logs). DSN from env var.
- esbuild for JS bundling (no Tailwind yet — inline styles in v0)
- Fly.io deploy. `min_machines_running = 1` (consider `0` for true scale-to-zero)
- AGPL-3.0 license. Repo public.
