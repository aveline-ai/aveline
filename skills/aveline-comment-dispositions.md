# Aveline: comment dispositions for agent edits

When you (an agent) submit a new doc version via `PATCH /api/workspaces/:slug/docs/:doc_slug`, you **must** declare what happens to every currently-open top-level comment thread on that doc. The server rejects the version (HTTP 422) if any open thread is missing or wrongly dispositioned.

This isn't bureaucracy — humans use comments to ask questions and flag issues. Forcing an explicit decision per thread keeps the conversation honest: every edit either *addresses* a question, *moves* it, or *acknowledges* it's still open.

## The contract

Include a `comment_dispositions` array on your update payload. Each entry:

```json
{
  "comment_id": "<uuid of the open top-level thread>",
  "action":     "resolve" | "reanchor" | "leave",
  "new_block_id": "<block id from the new version>",  // required iff action is "reanchor"
  "note":       "short reasoning for your decision"   // optional but encouraged
}
```

* **resolve** — your edit addresses the question. The thread closes; the version that resolved it (this one) is recorded so the UI can show "resolved in vN". Use this when you actually changed the doc to answer the question.
* **reanchor** — the thread is still open, but the block it pointed at has been split, merged, or renamed. Pick the closest equivalent block in your *new* `blocks` array and put its id in `new_block_id`. The comment stays open, anchored to the new block.
* **leave** — open, unchanged anchor. Use this when the thread isn't addressable in this edit ("out of scope here", "needs human input"). Always include a `note` explaining why — that note is visible to the human in the version history.

## Coverage

Before composing the payload:
1. Call `GET /api/workspaces/:slug/docs/:doc_slug/comments?status=open` (or read from the doc page) and list every comment where `resolved_at` is null and `parent_comment_id` is null.
2. Disposition every single one. Missing any → 422 `disposition_coverage_mismatch` with the missing ids in the response context.
3. Extra ids (already resolved, deleted, or replies) also → 422. Don't include them.

## Examples

A small edit that fixed exactly the question being asked:

```json
{
  "operations": [...],
  "intent": "tighten oncall escalation policy per cmt_abc",
  "comment_dispositions": [
    {"comment_id": "cmt_abc", "action": "resolve",
     "note": "rewrote section 3 to clarify the SEV1 path"}
  ]
}
```

A refactor that renamed a heading from "Setup" to "Getting Started":

```json
{
  "comment_dispositions": [
    {"comment_id": "cmt_xyz", "action": "reanchor",
     "new_block_id": "b_getting_started",
     "note": "block was renamed in this edit"}
  ]
}
```

A larger structural edit with mixed dispositions:

```json
{
  "comment_dispositions": [
    {"comment_id": "cmt_aaa", "action": "resolve",  "note": "replaced the wrong API URL"},
    {"comment_id": "cmt_bbb", "action": "reanchor", "new_block_id": "b_runbook_intro",
     "note": "intro paragraph absorbed the old block"},
    {"comment_id": "cmt_ccc", "action": "leave",
     "note": "needs product input on rollout date, will revisit next week"}
  ]
}
```

## Common mistakes

* **Treating "leave" as a no-op.** It's not — it's an acknowledgement. A human reads your `note` to know you saw the thread.
* **Picking a "close enough" block_id for reanchor without telling the human.** Always include a `note` explaining why this is the right new anchor.
* **Resolving threads you didn't actually address.** Humans can unresolve, and they will. Be honest.
* **Forgetting that doc-level comments (block_id null) still need dispositioning** — they're open threads too.
