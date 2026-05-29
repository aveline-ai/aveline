---
title: Sentry tips
slug: sentry-tips
owner: carol
pinned: false
tags: [stack, observability, runbook]
summary: Things that bit us while wiring Sentry 12.
---

# Sentry tips

A few sharp edges from getting Sentry 12 up.

## DSN gates everything

We only set `enable_logs: true` *when* `SENTRY_DSN` is in the env. Without
that guard, Sentry 12 crashes on startup with a `MatchError` in
`Sentry.Transport.get_endpoint_and_headers/0`.

## Logger handler is auto-attached

In Sentry 12, setting `enable_logs: true` auto-attaches the Logger handler.
Don't also call `:logger.add_handler/3` manually — you'll get duplicate
events.

## Hackney is required

The default HTTP client for Sentry 12 is `Sentry.HackneyClient`. You must
have `:hackney` in deps.

## Logs vs Issues

- A bare `Logger.info` / `Logger.error` shows up in **Logs**.
- A raised exception (or `Sentry.capture_exception/1`) shows up in **Issues**.

Don't reach for `capture_message` — use `Logger` at the right level.
