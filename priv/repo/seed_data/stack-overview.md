---
title: Stack overview
slug: stack-overview
owner: alice
pinned: true
tags: [onboarding, architecture, stack]
summary: One-page tour of the Aveline stack — what runs where.
---

# Stack overview

This is the 30-second version. Read [[architecture-decisions]] for the why.

## Runtime

- **Backend**: Phoenix 1.8 / Elixir 1.18+ on Fly.io (`app.aveline.ai`).
- **Database**: Postgres on Supabase, accessed via the *Session pooler*. Not the
  direct connection, not the transaction pooler.
- **Frontend**: LiveView. Same-origin with the API. No separate React client.
- **Landing**: static HTML on Cloudflare Pages (`aveline.ai`).
- **CLI**: Go binary, `github.com/aveline-ai/cli`, talks to the JSON API via
  bearer tokens.

## Where things live

| Concern        | Repo                | Notes                     |
| -------------- | ------------------- | ------------------------- |
| Backend + API  | `aveline-ai/aveline`| AGPL-3.0                  |
| CLI            | `aveline-ai/cli`    | MIT, goreleaser            |
| Landing        | `aveline-ai/landing`| Cloudflare Pages          |

## Logging + errors

Sentry 12 with `enable_logs: true`. `Logger` calls flow to Sentry Logs;
exceptions land in Issues. DSN is read from `SENTRY_DSN` only — local dev
has no DSN and Sentry is fully inert.

## Background work

Oban is configured but has no queues yet. We'll add them when something
actually needs to run async.
