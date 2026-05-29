---
title: Deploy guide
slug: deploy-guide
owner: bob
pinned: false
tags: [runbook, deploys, stack]
summary: How to ship the backend without breaking prod.
---

# Deploy guide

## Local pre-flight

```sh
mix format --check-formatted
mix credo --strict
mix test
mix assets.build
```

If any of these fail, fix before deploying. CI also runs them, but the
feedback loop is faster locally.

## Deploy

```sh
fly deploy
```

`fly.toml` is configured with `min_machines_running = 1` and
`auto_stop_machines = true`. Cold-start is ~2s; first request after a
sleep wakes the machine.

## Migrations

Migrations run automatically in the Dockerfile's release step. If a
migration is destructive, do it in two deploys: add the new column /
table first, deploy, backfill, then a follow-up deploy to remove the old
shape.

## Post-deploy check

```sh
curl https://app.aveline.ai/api/heartbeat
```

Should return `{"status":"ok","service":"aveline",...}`. Sentry will page
within ~60s if anything is exploding.

See also: [[oncall-runbook]] if something is on fire.
