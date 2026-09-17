# Agent instructions

## Team knowledge lives in Aveline

We keep shared knowledge (product docs, architecture, tickets, runbooks, feedback, etc.) in the `aveline` Aveline workspace, not in this repo. This workspace is the product's own knowledge base; dogfooding is the point. Read and write it through the `aveline` CLI (`aveline --help` lists every operation).

Start every session by running:

```
aveline -w aveline get-orientation
```

That doc explains how the workspace organizes its knowledge. Read it before touching any doc. Run `aveline contract` before your first doc write: it shows every block type and edit op with a valid example.

New docs are born private and new views land in your personal bucket. Publish deliberately: pass `--visibility workspace` on create-doc (or run `set-doc-visibility` after) for anything the team should see, and `--bucket team` on create-view for shared views.

To make `aveline` the default workspace so the `-w` flag is unnecessary, run `aveline use-workspace aveline` once.
