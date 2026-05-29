---
title: Architecture decisions
slug: architecture-decisions
owner: alice
pinned: true
tags: [onboarding, architecture, decisions]
summary: Running log of "why we picked X" so we don't re-litigate it.
---

# Architecture decisions

A decision log — append, don't rewrite. If a decision flips, add a new entry
that links the old one.

## 2026-04 — Phoenix LiveView over a separate SPA

The web UI is the *secondary* surface (agents are primary). Form-heavy +
real-time threading is LiveView's bullseye, and same-origin removes the
cookie/CSRF/CORS pain a React client would add. Revisit if a marketing
surface needs Next-style SSR.

## 2026-04 — Postgres via Supabase Session pooler

Direct connection is IPv6-only on Fly; transaction pooler breaks Ecto
prepared statements. The Session pooler is the only mode that works.

## 2026-05 — AGPL-3.0 backend, MIT CLI

Open by default. AGPL stops a competing SaaS fork from staying closed; MIT
on the client is the conventional ask. Leaves room for a future commercial
dual-license if an enterprise customer materializes.

## 2026-05 — Tags + saved views over a folder/project hierarchy

Hierarchies decay into "where did I put it?" Tags let one note belong to
multiple lenses, and a *view* is a saved tag intersection. Promote `tags`
to its own table only if query patterns demand it.

## 2026-05 — Soft-delete from day one

Deletion is a user action, not data destruction. Cheap on day one,
multi-week migration to retrofit later. Hard deletes are reserved for
membership rows and tokens.
