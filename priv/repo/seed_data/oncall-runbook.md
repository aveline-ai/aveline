---
title: Oncall runbook
slug: oncall-runbook
owner: bob
pinned: true
tags: [oncall, runbook]
summary: First things to do when an alert pages you.
---

# Oncall runbook

When a page hits, work top-down. Don't skip steps.

## 1. Acknowledge

Open the alert in Sentry. Click Acknowledge. Drop a note in
`#aveline-oncall` so other folks know you're on it.

## 2. Triage

- Is it the **API** (`app.aveline.ai`)? Check Fly metrics:
  `fly status -a aveline` and `fly logs -a aveline`.
- Is it the **landing** (`aveline.ai`)? Check Cloudflare Pages — almost
  certainly a deploy regression, roll back from the Pages UI.
- Is it the **database**? Supabase dashboard. The Session pooler can spike
  on connection storms — watch the pool utilization graph.

## 3. Mitigate

Roll back before you root-cause. `fly deploy --image <previous-sha>` if it's
the API. For landing, the rollback button is one click in Cloudflare.

## 4. Document

Add a `flagged` item with what broke and a short remediation note. Tag it
`oncall` and `incident`. The post-mortem is async.

## Escalation

If you're stuck > 20 minutes, page the other oncall. We do not have a third
tier yet — fall back to "wake Arie" if the second oncall doesn't pick up.
