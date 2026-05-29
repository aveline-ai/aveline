# Aveline v0 Spec — Foundations

This is the contract for v0. Backend, CLI, and (later) LiveView agents build
against this spec independently. If the spec is ambiguous, ask before
inventing.

Design principles in `PRODUCT.md` apply — especially: minimal hidden state,
API-time validation, soft-delete from day one.

---

## Scope

**In v0**: workspaces, tagged + pinnable items, saved views (tag filters),
manually-seeded users + bearer tokens, JSON API, simple LiveView browser.

**Deferred**: messages/threads, item version history, status enum
(active/flagged/retired), mentions, signup UI, workspace invite UI,
notifications, attachments.

The foundation (soft-delete columns, tag arrays, workspace scoping, bearer
auth) lands now so v0.1+ doesn't require painful migrations.

---

## Data Model

UUID primary keys. `inserted_at` + `updated_at` on every table. Soft-delete
columns on every user-facing entity.

```
users                          (extend existing)
  + email           text  unique not null
  + display_name    text

workspaces
  id               uuid pk
  slug             text  unique not null     -- [a-z0-9][a-z0-9-]*
  name             text  not null
  created_by_id    uuid  fk users
  deleted_at       timestamptz
  deleted_by_id    uuid  fk users
  inserted_at, updated_at

workspace_memberships
  id               uuid pk
  workspace_id     uuid  fk workspaces (on delete: cascade)
  user_id          uuid  fk users
  role             text  not null default 'member'   -- 'member' | 'admin' (only 'member' used in v0)
  inserted_at, updated_at
  unique(workspace_id, user_id)
  -- hard delete only; relationship row, not user content

items
  id               uuid pk
  workspace_id     uuid  fk workspaces
  slug             text  not null            -- unique per workspace (among non-deleted)
  title            text  not null            -- <= 200 chars
  body             text  not null default '' -- markdown
  summary          text                       -- optional one-liner
  tags             text[] not null default '{}'   -- each tag matches slug format, max 16
  pinned           bool  not null default false
  owner_id         uuid  fk users not null
  created_by_id    uuid  fk users not null
  created_via      text  not null            -- 'cli' | 'web' | 'seed'
  deleted_at       timestamptz
  deleted_by_id    uuid  fk users
  inserted_at, updated_at
  index(workspace_id) where deleted_at is null
  gin index(tags)

views
  id               uuid pk
  workspace_id     uuid  fk workspaces
  slug             text  not null            -- unique per workspace
  name             text  not null
  tag_filter       text[] not null default '{}'  -- items match if tags ⊇ tag_filter (intersection)
  description      text
  created_by_id    uuid  fk users
  deleted_at       timestamptz
  deleted_by_id    uuid  fk users
  inserted_at, updated_at

api_tokens
  id               uuid pk
  user_id          uuid  fk users
  name             text  not null            -- human label, e.g. "arie laptop"
  token_hash       text  not null unique     -- sha256 hex of plaintext token
  token_prefix     text  not null            -- first 8 chars of plaintext, for display
  last_used_at     timestamptz
  revoked_at       timestamptz
  inserted_at, updated_at
  -- hard delete via revoked_at; no soft-delete columns
```

### Design notes

- **Tag semantics**: a view's `tag_filter` matches items whose `tags`
  contains ALL of the filter tags (intersection). Within an item, tags is a
  set. Tags are lowercase, slug-format, max 16 per item.
- **Pinned is orthogonal to views**. A view defines a slice; whether to load
  only pinned items inside that slice is a query-time choice. Claude's
  "attach" flow = "list items in view X where pinned=true".
- **Soft-delete pattern**: every context exposes `base_query/0` filtering
  `where is_nil(deleted_at)`. Default list queries use it; direct fetches
  by id/slug can opt out to render a "deleted" banner.
- **Token format**: plaintext shown once is `avl_<32 url-safe chars>`. Store
  `sha256_hex(plaintext)` + first 8 plaintext chars for display
  ("avl_abc12345..."). Plaintext is never persisted.

---

## API Contract

All `/api/*` routes (except `/api/heartbeat`) require
`Authorization: Bearer avl_...`.

### Error envelope

Every non-2xx response:

```json
{
  "error": {
    "code": "snake_case_code",
    "message": "human readable",
    "field": "optional field name",
    "context": { }
  }
}
```

Codes used in v0: `unauthorized`, `forbidden`, `not_found`,
`validation_failed`, `slug_taken`, `workspace_not_found`, `tag_invalid`.

### Endpoints

```
GET    /api/heartbeat                                  (open)
GET    /api/me                                         current user + my workspaces
GET    /api/workspaces                                 workspaces I'm a member of
GET    /api/workspaces/:slug                           one workspace

GET    /api/workspaces/:slug/items                     ?pinned=true&tag=X&tag=Y&view=SLUG
GET    /api/workspaces/:slug/items/:item_slug
POST   /api/workspaces/:slug/items
PATCH  /api/workspaces/:slug/items/:item_slug
DELETE /api/workspaces/:slug/items/:item_slug          soft delete
POST   /api/workspaces/:slug/items/:item_slug/restore

GET    /api/workspaces/:slug/views
GET    /api/workspaces/:slug/views/:view_slug          view + matching items
POST   /api/workspaces/:slug/views
PATCH  /api/workspaces/:slug/views/:view_slug
DELETE /api/workspaces/:slug/views/:view_slug
```

### Request shapes

**POST /api/workspaces/:slug/items**

```json
{
  "title": "string (required, <= 200)",
  "body":  "string (markdown, default '')",
  "summary": "string | null",
  "tags": ["string"],
  "pinned": false,
  "slug": "string (optional; auto-derived from title if absent)"
}
```

**PATCH /api/workspaces/:slug/items/:item_slug**

Any subset of: `title`, `body`, `summary`, `tags`, `pinned`. `tags` replaces
the whole array (clients implement add/remove client-side or pre-fetch).

**POST /api/workspaces/:slug/views**

```json
{
  "slug": "string",
  "name": "string",
  "tag_filter": ["string"],
  "description": "string | null"
}
```

### Response shapes

**Item JSON**:

```json
{
  "id": "uuid",
  "slug": "string",
  "title": "string",
  "body": "string",
  "summary": "string | null",
  "tags": ["string"],
  "pinned": false,
  "owner": { "id": "uuid", "username": "string", "display_name": "string | null" },
  "created_by": { "id": "uuid", "username": "string", "display_name": "string | null" },
  "created_via": "cli | web | seed",
  "inserted_at": "iso8601",
  "updated_at": "iso8601",
  "deleted_at": "iso8601 | null"
}
```

**Workspace JSON**:

```json
{
  "id": "uuid", "slug": "string", "name": "string",
  "inserted_at": "iso8601", "updated_at": "iso8601",
  "deleted_at": "iso8601 | null"
}
```

**View JSON**:

```json
{
  "id": "uuid", "slug": "string", "name": "string",
  "tag_filter": ["string"], "description": "string | null",
  "inserted_at": "iso8601", "updated_at": "iso8601",
  "deleted_at": "iso8601 | null"
}
```

`GET /api/workspaces/:slug/views/:view_slug` returns the view plus its
matching items:

```json
{ "view": { ... }, "items": [ {item}, {item}, ... ] }
```

`GET /api/me` returns:

```json
{ "user": {"id","username","email","display_name"},
  "workspaces": [ {workspace}, ... ] }
```

List endpoints wrap arrays: `{ "items": [...] }`, `{ "views": [...] }`,
`{ "workspaces": [...] }`.

### Validation (server-side; principle 2)

- workspace member check on every workspace-scoped action → `403 forbidden`
- workspace not found → `404 workspace_not_found`
- slug format `[a-z0-9][a-z0-9-]*`, length 1–60
- slug uniqueness scoped to (workspace, non-deleted) → `422 slug_taken`
- title required, <= 200 chars
- each tag matches slug format → `422 tag_invalid`
- max 16 tags per item
- view `tag_filter` may be empty (matches all items in workspace)

---

## CLI Contract — `aveline`

Binary name: `aveline`. Built with cobra + viper. Module path:
`github.com/aveline-ai/cli`.

### Config

File `~/.config/aveline/config.toml`:

```toml
api_url = "https://app.aveline.ai"
token = "avl_..."
workspace = "stable-pod"
```

`api_url` defaults to `https://app.aveline.ai`. Override via `--api-url` or
env `AVELINE_API_URL`.

### Verbs (v0)

```
aveline login [--api-url URL]                  interactive; stores token
aveline whoami                                  GET /api/me; prints user + workspaces

aveline workspace list
aveline workspace use <slug>                    writes to config

aveline list [--pinned] [--tag X]... [--view SLUG]
aveline get <slug>                              prints markdown body to stdout
aveline save --title "..." [--body -|FILE]
             [--tag X]... [--pin] [--summary "..."]
             [--slug SLUG]
aveline edit <slug> [--title ...] [--body -|FILE]
             [--add-tag X]... [--remove-tag X]...
             [--pin|--unpin] [--summary "..."]
aveline delete <slug>
aveline restore <slug>

aveline view list
aveline view get <slug>                         view metadata + matching items
aveline view create <slug> --name "..." [--tag X]... [--description "..."]
aveline view edit <slug> [--name ...] [--add-tag X]... [--remove-tag X]...
aveline view delete <slug>
```

### Behavior

- Default output: human-readable. `--json` flag everywhere prints the raw
  API response (this is what Claude will use).
- Every request adds `Authorization: Bearer <token>` from config; if absent,
  prompt to run `aveline login`.
- Error envelope from server is rendered as-is — never reworded
  client-side. Exit code nonzero on any error.
- `--body -` reads stdin; `--body FILE` reads that file. Body defaults to
  empty if omitted.
- `--add-tag` / `--remove-tag` on `edit` are implemented by GET-ing the item
  first, computing the new tags array, then PATCH-ing.
- `aveline save` auto-derives `slug` from title if `--slug` not provided
  (lowercase, replace runs of non-alnum with `-`, trim leading/trailing `-`).

---

## Seed Task (backend)

`mix aveline.seed` — idempotent:

1. Creates a user from env vars `SEED_USER_EMAIL`, `SEED_USER_USERNAME`,
   `SEED_USER_DISPLAY_NAME` (no-op if user exists).
2. Creates a workspace from `SEED_WORKSPACE_SLUG`, `SEED_WORKSPACE_NAME`.
3. Adds the user as a member.
4. Issues an API token, prints the plaintext **once** (`avl_<random>`).
   Stores hash + prefix.

Local: `mix aveline.seed`. Prod: `fly ssh console -C "/app/bin/aveline eval 'Mix.Task.run(\"aveline.seed\")'"`.

---

## End-to-end verification

After backend + CLI are wired:

1. `mix ecto.create && mix ecto.migrate && mix aveline.seed` → get token.
2. `aveline login --api-url http://localhost:4000`, paste token;
   `aveline whoami` → seeded user + workspace.
3. `aveline workspace use <slug>`.
4. `aveline save --title "Oncall rotation" --tag oncall --pin`, then
   `aveline list --pinned --tag oncall` shows it.
5. `aveline view create oncall --name "Oncall" --tag oncall`, then
   `aveline view get oncall --json` returns view + items.
6. `aveline delete oncall-rotation`, `aveline list` excludes it,
   `aveline restore oncall-rotation` brings it back.
7. (After LiveView lands) open `/w/<slug>` in browser.
