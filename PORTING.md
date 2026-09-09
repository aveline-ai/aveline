# Gleam DI port — conventions

We are moving API endpoint logic into pure Gleam handlers. Elixir/Phoenix
stays the shell: routing, auth plugs, Ecto, PubSub. Gleam is the heart:
every decision an endpoint makes. IO is injected as a `Ctx` of capability
closures ("DI approach").

Read these files first — they are the exemplar, copy their style exactly:

- `src/aveline/handlers/doc_kudos.gleam` — a ported handler
- `src/aveline/caps/kudos.gleam` + `lib/aveline/gleam/caps/kudos.ex` — a caps pair
- `src/aveline/docs/access.gleam`, `src/aveline/docs/permissions.gleam` — shared doc rules
- `lib/aveline_web/controllers/api/doc_controller.ex` (`def kudos`) — a rewired controller action
- `test/aveline/doc_kudos_test.gleam` + `test/aveline/fakes.gleam` — pure handler tests
- `test/aveline_web/controllers/api/doc_kudos_api_test.exs` — integration lock

## Architecture

```
Phoenix plug pipeline (auth, workspace scope)        [Elixir, unchanged]
  -> controller action: params -> typed request      [Elixir, thin]
  -> handler(ctx, scope, request) -> Result(resp, ApiError)   [GLEAM, all logic]
       ctx.<domain>.<cap>(...) performs injected IO
  -> Envelope/GleamAdapter renders result            [Elixir, thin]
```

- `Scope` (workspace + actor) comes from `CtxBuilder.scope(conn)`.
- `Ctx` comes from `CtxBuilder.build()`.
- Handler errors are `aveline/core/error.ApiError`; `GleamAdapter.error/1`
  maps them onto the existing FallbackController tuples. Reuse the
  existing error codes exactly (see fallback_controller.ex) — API
  behavior must not change.

## File ownership (parallel porting — IMPORTANT)

You own, per domain `<d>`:

- `src/aveline/caps/<d>.gleam` — fill in the placeholder caps record + `stub()`
- `lib/aveline/gleam/caps/<d>.ex` — the real closures (field order in lockstep!)
- `src/aveline/<d>/…` — domain types + pure rules modules
- `src/aveline/handlers/…` — your handlers (one module per resource is fine)
- `lib/aveline_web/controllers/api/<your>_controller.ex` — rewire actions
- `test/aveline/<d>_…_test.gleam`, `test/aveline/<d>_fixtures.gleam` — your tests
- `test/aveline_web/controllers/api/…` — your integration tests

Do NOT edit (stable shared surface): `src/aveline/core/ctx.gleam`,
`test/aveline/fakes.gleam`, `lib/aveline/gleam/ctx_builder.ex`,
`src/aveline/core/{scope,error,events}.gleam`, another domain's files.
If you genuinely need a cap from another domain (e.g. docs access checks),
use the existing `ctx.docs` / `aveline/docs/access` — they are already
wired. Need a new shared thing? Note it in your final report instead of
adding it.

Exception: an empty placeholder caps constructor (`TagsCaps`) compiles to
a bare atom; once you add fields it becomes a tagged tuple — your Elixir
`build/0` must match (the placeholders note this).

## Boundary conventions

| Gleam | Erlang/Elixir |
|---|---|
| `Ok(x)` / `Error(e)` | `{:ok, x}` / `{:error, e}` |
| `Some(x)` / `None` | `{:some, x}` / `:none` (`Aveline.Gleam.Interop.opt/unopt`) |
| record `Foo(a, b)` | `{:foo, a, b}` |
| no-field constructor `Bar` | `:bar` |
| `String` | UTF-8 binary |
| constructor `WorkspaceVisible` | `:workspace_visible` |

Rules:
- Caps take/return Gleam domain types, never Ecto structs, maps, or
  Dynamic. The Elixir cap closure does the conversion.
- Fine-grained caps (one query/statement each) wherever the handler makes
  decisions. Coarse caps are acceptable ONLY for heavy read/reporting SQL
  (search, facet counts, pagination) and the block/chart engine — there
  the Gleam handler still owns param validation, access checks, and
  response assembly, delegating one `list_x(filters)` cap.
- Caps whose failures handlers don't branch on return plain values and
  raise Elixir-side (surfaces as 500, same as before). Caps whose
  failures ARE product behavior (uniqueness conflicts etc.) return
  `Result` and the handler maps them to the existing error codes.
- Timestamps crossing into Gleam: pass ISO8601 `String` for display
  values (keep it simple for v1).
- JSON-ish free-form payloads (block data, event data): keep them on the
  Elixir side or pass through opaquely; do not port the block engine.

## Behavior parity

This is a refactor, not a redesign. Every endpoint must return the same
envelope, codes, and side effects (events recorded, broadcasts published)
as before. Port the logic in the controller action AND the pieces of the
context function it calls that are decision logic; leave pure-SQL bits as
caps. When the old code logs an activity event, the Gleam handler does it
via `ctx.events.record` (see doc_kudos).

## Workflow

- `gleam check` / `gleam test` — fast, no DB. Write pure handler tests
  for every branch (errors included); stubs panic so untouched IO fails
  loudly.
- Quirk: if `gleam test` dies with "function did not exist" after a
  `mix compile`, run `rm -rf build` and retry (mix and the gleam CLI
  share `build/` but mix skips beam generation).
- `mix compile` must pass with no warnings in your files.
- Write/extend an ExUnit integration test for each rewired action
  (`test/aveline_web/controllers/api/…`). If you're in a shared checkout,
  do NOT run `mix test` (DB races with other agents) — the coordinator
  runs it; in your own worktree it's fine (`mix test path/to/file.exs`).
- `gleam format src test` before finishing. Do not commit — report back.
