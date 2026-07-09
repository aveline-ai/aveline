# Local development seed data.
#
#   mix ecto.reset   # ← canonical: drops + recreates + migrates + seeds
#   mix run priv/repo/seeds.exs   # ← idempotent re-seed without drop
#
# Deterministic. Three users, one workspace, hardcoded tokens, agent-authored
# docs (each with multiple versions to demonstrate the changelog), mixed
# human + agent comments, plus a sprinkle of kudos / views / pin toggles /
# resolves so the Activity tab has interesting traffic on first load.
#
# Every mutation flows through the standard contexts, so the events table
# captures all of it automatically — we don't synthesize events here.

import Ecto.Query

alias Aveline.Accounts
alias Aveline.Docs
alias Aveline.Comments
alias Aveline.DocViews
alias Aveline.Events
alias Aveline.Kudos
alias Aveline.Repo
alias Aveline.Tags
alias Aveline.Tokens.ApiToken
alias Aveline.Workspaces

# ===== Users =====

user_specs = [
  %{
    email: "alice@local.test",
    username: "alice",
    display_name: "Alice",
    token: "avl_locseed_alice_aaaaaaaaaaaaaaaaaa"
  },
  %{
    email: "bob@local.test",
    username: "bob",
    display_name: "Bob",
    token: "avl_locseed_bob_bbbbbbbbbbbbbbbbbbbb"
  },
  %{
    email: "carol@local.test",
    username: "carol",
    display_name: "Carol",
    token: "avl_locseed_carol_cccccccccccccccccc"
  }
]

upsert_user = fn spec ->
  case Accounts.get_user_by_email(spec.email) do
    nil ->
      {:ok, u} =
        Accounts.create_user(%{
          "email" => spec.email,
          "username" => spec.username,
          "display_name" => spec.display_name
        })

      u

    u ->
      u
  end
end

users = Enum.map(user_specs, fn spec -> {spec, upsert_user.(spec)} end)
[{_, first_user} | _] = users
users_by_username = Map.new(users, fn {spec, u} -> {spec.username, u} end)

# ===== Workspace + memberships =====

workspace_slug = "local-pod"

workspace =
  case Workspaces.get_active_by_slug(workspace_slug) do
    nil ->
      {:ok, w} =
        Workspaces.create_workspace(%{
          "slug" => workspace_slug,
          "name" => "Local Pod",
          "created_by_id" => first_user.id
        })

      w

    w ->
      w
  end

Enum.each(users, fn {spec, u} ->
  case Workspaces.get_membership(workspace.id, u.id) do
    nil ->
      {:ok, _} = Workspaces.ensure_member(workspace.id, u.id)

      Events.record(%{
        workspace_id: workspace.id,
        actor: u.id,
        actor_type: "human",
        action: "member_joined",
        target_kind: "user",
        target_id: u.id,
        target_label: spec.username
      })

    _ ->
      :ok
  end
end)

# ===== Tokens =====

hash = fn plaintext ->
  :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
end

Enum.each(users, fn {spec, u} ->
  h = hash.(spec.token)

  case Repo.one(from t in ApiToken, where: t.token_hash == ^h) do
    nil ->
      %ApiToken{}
      |> ApiToken.changeset(%{
        user_id: u.id,
        name: "local seed",
        token_hash: h,
        token_prefix: String.slice(spec.token, 0, 8)
      })
      |> Repo.insert!()

    _ ->
      :ok
  end
end)

# ===== Docs =====
# Each is created as agent-authored (per product wedge: agents own content).
# After creation we optionally edit a few via apply_ops to demonstrate the
# version history feature.

alice = users_by_username["alice"]
bob = users_by_username["bob"]
carol = users_by_username["carol"]

t = fn text -> %{"text" => text} end
b = fn text, marks -> %{"text" => text, "marks" => marks} end

para = fn spans -> %{"type" => "paragraph", "content" => spans} end
heading = fn level, text -> %{"type" => "heading", "level" => level, "text" => text} end
code = fn lang, content -> %{"type" => "code", "language" => lang, "content" => content} end
ul = fn items ->
  %{
    "type" => "list",
    "ordered" => false,
    "items" => Enum.map(items, fn spans -> %{"content" => spans} end)
  }
end
ol = fn items ->
  %{
    "type" => "list",
    "ordered" => true,
    "items" => Enum.map(items, fn spans -> %{"content" => spans} end)
  }
end
# Slug form — the server resolves `doc` to the target's base_doc_id.
doc_link = fn slug, note ->
  %{"type" => "doc_link", "doc" => slug, "note" => [%{"text" => note}]}
end
# Inline mention: a span linking another doc from inside prose. Same
# slug resolution as doc_link blocks; the text stays the author's words.
mention = fn text, slug -> %{"text" => text, "link" => %{"doc" => slug}} end

# ===== Tags =====
# Every tag carries a description (required, 1..280 chars). Pre-created
# here so doc inserts below pass Tag-exists validation.

tag_specs = [
  {"architecture", "How the system is shaped and the why behind those calls."},
  {"database", "Postgres schema, migrations, query patterns, and indexing."},
  {"decisions", "ADRs and other choices that should not be re-litigated."},
  {"deploys", "Shipping the backend — pre-flight, deploy steps, rollback."},
  {"dev", "Local development — setup, tooling, day-to-day workflows."},
  {"examples", "Worked examples and reference snippets for common tasks."},
  {"observability", "Logs, metrics, alerting, error tracking, dashboards."},
  {"oncall", "What to do when paged — triage flows and escalation."},
  {"onboarding", "Read-these-first content for new teammates."},
  {"runbook", "Operational playbooks for live incidents."},
  {"stack", "The components Aveline runs on and how they fit together."},
  # status:* and the other baseline tags come from the workspace
  # template (seeded by create_workspace).
  {"kanban-feature", "Work on the kanban board feature itself."}
]

Enum.each(tag_specs, fn spec ->
  {slug, description, color} =
    case spec do
      {s, d} -> {s, d, nil}
      {s, d, c} -> {s, d, c}
    end

  case Tags.get(workspace.id, slug) do
    nil -> {:ok, _} = Tags.create(workspace.id, slug, description, alice.id, color: color)
    _ -> :ok
  end
end)

doc_specs = [
  %{
    slug: "stack-overview",
    title: "Stack overview",
    summary: "One-page tour of the Aveline stack — what runs where.",
    owner: alice,
    tags: ["onboarding", "architecture", "stack"],
    blocks: [
      para.([
        t.("Aveline runs as a Phoenix 1.8 app on "),
        b.("Fly.io", ["bold"]),
        t.(", backed by Postgres reached via "),
        b.("DATABASE_URL", ["code"]),
        t.(" (provider-agnostic).")
      ]),
      heading.(2, "Where things live"),
      ul.([
        [t.("Backend + API: "), b.("aveline-ai/aveline", ["code"])],
        [t.("CLI: "), b.("aveline-ai/cli", ["code"])],
        [t.("Landing: "), b.("aveline-ai/landing", ["code"])]
      ]),
      heading.(2, "Background work"),
      para.([
        t.("Oban is configured but has no queues yet. We add them when something actually needs to run async.")
      ])
    ]
  },
  %{
    slug: "architecture-decisions",
    title: "Architecture decisions",
    summary: "Running log of \"why we picked X\" so we don't re-litigate it.",
    owner: alice,
    tags: ["onboarding", "architecture", "decisions"],
    blocks: [
      heading.(2, "Phoenix LiveView over a separate SPA"),
      para.([
        t.("The web UI is the secondary surface — agents are primary. Real-time threading + form-heavy is LiveView's bullseye, and same-origin removes the cookie/CSRF/CORS pain a React client would add.")
      ]),
      heading.(2, "Block format over markdown"),
      para.([
        t.("Notes are stored as structured blocks, not markdown. Lets us diff at the block level, link to specific paragraphs, attach metadata per block, and represent agent intent. Markdown is a substrate for human authoring; we serve a different need.")
      ])
    ]
  },
  %{
    slug: "oncall-runbook",
    title: "Oncall runbook",
    summary: "First things to do when an alert pages you.",
    owner: bob,
    tags: ["oncall", "runbook"],
    blocks: [
      heading.(2, "1. Acknowledge"),
      para.([
        t.("Open the alert in Sentry. Click Acknowledge. Drop a note in #aveline-oncall so the other oncall knows you're on it.")
      ]),
      heading.(2, "2. Triage"),
      ol.([
        [b.("API", ["bold"]), t.(" ("), b.("app.aveline.ai", ["code"]), t.("): check Fly logs.")],
        [b.("Landing", ["bold"]), t.(": Cloudflare Pages — almost certainly a deploy regression, roll back.")],
        [b.("Database", ["bold"]), t.(": pool + slow-query graphs in the managed PG dashboard.")]
      ]),
      heading.(2, "3. Mitigate, then root-cause"),
      para.([
        t.("Rolling back is always the first move. Investigate after the page is closed.")
      ])
    ]
  },
  %{
    slug: "deploy-guide",
    title: "Deploy guide",
    summary: "How to ship the backend without breaking prod.",
    owner: bob,
    tags: ["runbook", "deploys", "stack"],
    blocks: [
      heading.(2, "Local pre-flight"),
      code.("sh", "mix format --check-formatted\nmix credo --strict\nmix test\nmix assets.build"),
      heading.(2, "Deploy"),
      code.("sh", "fly deploy"),
      para.([
        t.("Cold-start is ~2s. Sentry pages within 60s if anything explodes.")
      ])
    ]
  },
  %{
    slug: "local-dev-setup",
    title: "Local dev setup",
    summary: "Get the backend, API, and CLI talking on your laptop.",
    owner: alice,
    tags: ["onboarding", "dev"],
    blocks: [
      heading.(2, "Prereqs"),
      ul.([
        [t.("Erlang/OTP 27+")],
        [t.("Elixir 1.18+")],
        [t.("Postgres 15+")]
      ]),
      heading.(2, "Backend"),
      code.("sh", "git clone git@github.com:aveline-ai/aveline.git\ncd aveline\nmix deps.get\nmix ecto.setup\nmix phx.server"),
      para.([t.("The seed task prints three local tokens (alice / bob / carol).")])
    ]
  },
  %{
    slug: "sentry-tips",
    title: "Sentry tips",
    summary: "Things that bit us while wiring Sentry 12.",
    owner: alice,
    tags: ["stack", "observability", "runbook"],
    blocks: [
      heading.(2, "DSN gates everything"),
      para.([
        t.("We only set "),
        b.("enable_logs: true", ["code"]),
        t.(" when "),
        b.("SENTRY_DSN", ["code"]),
        t.(" is in the env. Without that guard, Sentry 12 crashes on startup.")
      ]),
      heading.(2, "Logs vs Issues"),
      ul.([
        [b.("Logger.info", ["code"]), t.(" / "), b.("Logger.error", ["code"]), t.(" → Logs")],
        [b.("Sentry.capture_exception/1", ["code"]), t.(" → Issues")]
      ])
    ]
  },
  %{
    slug: "database-notes",
    title: "Database notes",
    summary: "Conventions and gotchas for the Postgres schema.",
    owner: bob,
    tags: ["stack", "database"],
    blocks: [
      heading.(2, "UUIDs everywhere"),
      para.([
        t.("Every table uses UUID primary keys via "),
        b.("gen_random_uuid()", ["code"]),
        t.(". Don't introduce serial IDs.")
      ]),
      heading.(2, "Soft delete"),
      para.([
        t.("Versioned tables use "),
        b.("deleted_at", ["code"]),
        t.(" as both supersession marker and user-delete marker. "),
        b.("deleted_by_id", ["code"]),
        t.(" disambiguates.")
      ])
    ]
  },
  %{
    slug: "code-examples",
    title: "Code blocks — every language at a glance",
    summary: "A grab-bag of snippets to sanity-check syntax highlighting + monospace rendering.",
    owner: alice,
    tags: ["stack", "examples"],
    blocks: [
      para.([
        t.("One snippet per common language. Useful as a visual regression check when the block renderer changes.")
      ]),
      heading.(2, "Elixir"),
      code.("elixir", """
      defmodule Aveline.Blocks.Document do
        def apply_ops(blocks, ops) do
          Enum.reduce_while(ops, {:ok, blocks}, fn op, {:ok, acc} ->
            case apply_op(acc, op) do
              {:ok, next} -> {:cont, {:ok, next}}
              err -> {:halt, err}
            end
          end)
        end
      end
      """ |> String.trim()),
      heading.(2, "JavaScript"),
      code.("javascript", """
      const Hooks = {
        ResetOnEvent: {
          mounted() {
            const evt = this.el.dataset.resetEvent || "reset-form"
            window.addEventListener(`phx:${evt}`, () => this.el.reset())
          }
        }
      }
      """ |> String.trim()),
      heading.(2, "SQL"),
      code.("sql", """
      SELECT i.title, i.version_number, i.intent
      FROM docs i
      WHERE i.base_doc_id = $1
      ORDER BY i.version_number DESC
      LIMIT 10;
      """ |> String.trim()),
      heading.(2, "Python"),
      code.("python", """
      from anthropic import Anthropic

      client = Anthropic()

      response = client.messages.create(
          model="claude-opus-4-7",
          max_tokens=1024,
          messages=[{"role": "user", "content": "summarize this note"}],
      )
      print(response.content[0].text)
      """ |> String.trim()),
      heading.(2, "Shell"),
      code.("sh", """
      curl -s http://localhost:4000/api/heartbeat \\
        -H "Authorization: Bearer avl_..." \\
        | jq .
      """ |> String.trim()),
      heading.(2, "Plain (no language)"),
      code.(nil, """
      Just some plain text without a language label.
      Useful for ASCII diagrams or arbitrary fixed-width content.

        +------+    +------+
        | item | -> | item |
        +------+    +------+
      """ |> String.trim())
    ]
  }
]

# Issue-style docs demoing the tag-driven Board view
# (scope tag kanban-feature + one status tag each).
issue = fn title, body, owner, status ->
  %{
    slug: title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-"),
    title: title,
    summary: body,
    owner: owner,
    tags: ["kanban-feature", "status:" <> status],
    blocks: [para.([t.(body)])]
  }
end

doc_specs =
  doc_specs ++
    [
      issue.("Kanban: drag & drop in the web", "Web is read-only for now (humans comment); revisit if pointing at cards ever beats asking your agent.", carol, "backlog"),
      issue.("Kanban: board block inside worklogs", "Embed a feature's own board under its worklog prose. Should already work — verify and demo it.", bob, "todo"),
      issue.("Kanban: ship boards-as-docs", "board block + scoped status tags + the Boards directory tab.", alice, "in-progress"),
      issue.("Kanban: settle the tag model", "Scoped tags (status:todo) with per-scope exclusivity. Decided.", alice, "done"),
      %{
        slug: "kanban-feature-notes",
        title: "Kanban feature — notes",
        summary: "Working notes for the kanban feature. The live board is the kanban-feature VIEW (sidebar).",
        owner: alice,
        tags: [],
        blocks: [
          para.([
            t.("Everything tagged "),
            b.("kanban-feature", ["code"]),
            t.(" lives in the "),
            b.("kanban-feature", ["code"]),
            t.(" view (pinned in the sidebar), grouped by "),
            b.("status", ["code"]),
            t.(". Agents move cards by retagging: "),
            b.("aveline apply-ops <slug> --tag kanban-feature --tag status:done --ops \"[]\"", ["code"])
          ])
        ]
      }
    ]

# Create docs if they don't already exist (idempotent).
created_docs =
  Enum.map(doc_specs, fn spec ->
    case Docs.get_current_by_slug(workspace.id, spec.slug) do
      nil ->
        {:ok, doc} =
          Docs.create_doc(%{
            workspace_id: workspace.id,
            owner_id: spec.owner.id,
            actor_user_id: spec.owner.id,
            actor_type: "agent",
            slug: spec.slug,
            title: spec.title,
            summary: spec.summary,
            tags: spec.tags,
            blocks: spec.blocks,
            intent: "initial seed: write the #{spec.slug} note"
          })

        doc

      existing ->
        existing
    end
  end)

# ===== Story: a doc that chains other docs via doc_link blocks =====
# Created after the targets above so slug resolution succeeds.

if is_nil(Docs.get_current_by_slug(workspace.id, "onboarding-story")) do
  {:ok, _story} =
    Docs.create_doc(%{
      workspace_id: workspace.id,
      owner_id: alice.id,
      actor_user_id: alice.id,
      actor_type: "agent",
      slug: "onboarding-story",
      title: "Story: new teammate onboarding",
      summary: "Guided trail through the docs a new teammate (or their agent) should read, in order.",
      tags: ["onboarding"],
      blocks: [
        para.([
          t.("Read these in order. Each stop is a doc_link block — fetch each with "),
          b.("aveline get-doc", ["code"]),
          t.(". Docs can also be mentioned inline: skim "),
          mention.("the stack overview", "stack-overview"),
          t.(" first if you're brand new.")
        ]),
        doc_link.("local-dev-setup", "Start here — get the app running on your machine."),
        doc_link.("stack-overview", "Then the shape of the system: what runs where."),
        doc_link.("architecture-decisions", "The why behind the shape. Don't re-litigate these."),
        doc_link.("oncall-runbook", "Finally: what to do when it breaks.")
      ],
      intent: "seed a story doc demonstrating doc_link chains"
    })
end

# ===== Versions: demonstrate the changelog on a couple of docs =====

# For stack-overview, append a new paragraph (v2)
stack = Enum.find(created_docs, &(&1.slug == "stack-overview"))

if stack && stack.version_number == 1 do
  new_block = %{
    "type" => "paragraph",
    "content" => [
      %{"text" => "Updated: we now also broadcast every doc mutation on PubSub topics like "},
      %{"text" => "doc:<base_doc_id>", "marks" => ["code"]},
      %{"text" => " so LiveViews update in real time."}
    ],
    "metadata" => %{"content_intent" => "document the pubsub addition"}
  }

  ops = [
    %{
      "op" => "append_block",
      "block" => new_block,
      "metadata" => %{"diff_intent" => "mention pubsub broadcasts now that they're wired"}
    }
  ]

  {:ok, _v2} =
    Docs.apply_ops(stack, ops, %{actor_user_id: alice.id, actor_type: "agent"},
      intent: "Mention the new PubSub broadcasts",
      resolves_comment_ids: []
    )
end

# For oncall-runbook, two follow-up edits to show v3 history
oncall = Enum.find(created_docs, &(&1.slug == "oncall-runbook"))

if oncall && oncall.version_number == 1 do
  ops_v2 = [
    %{
      "op" => "append_block",
      "block" => %{
        "type" => "heading",
        "level" => 2,
        "text" => "Escalation"
      },
      "metadata" => %{"diff_intent" => "add the escalation header"}
    },
    %{
      "op" => "append_block",
      "block" => %{
        "type" => "paragraph",
        "content" => [
          %{"text" => "If stuck > 20 minutes, page the other oncall. We do not have a third tier."}
        ]
      },
      "metadata" => %{"diff_intent" => "spell out the escalation policy"}
    }
  ]

  {:ok, v2} =
    Docs.apply_ops(oncall, ops_v2, %{actor_user_id: bob.id, actor_type: "agent"},
      intent: "Add escalation section after we forgot it last week"
    )

  # v3: tweak the existing heading text via modify_block
  first_block = List.first(v2.blocks)

  if first_block && first_block["type"] == "heading" do
    {:ok, _v3} =
      Docs.apply_ops(
        v2,
        [
          %{
            "op" => "modify_block",
            "id" => first_block["id"],
            "patch" => %{"text" => "1. Acknowledge (within 5 minutes)"},
            "metadata" => %{"diff_intent" => "be explicit about the SLA"}
          }
        ],
        %{actor_user_id: bob.id, actor_type: "agent"},
        intent: "Bake the 5-minute SLA into the runbook itself"
      )
  end
end

# ===== Thread messages =====
# Mix of human + agent commenters so the actor icons render meaningfully.
# Anchored to a specific doc version (the CURRENT version at seed time).

current = fn slug ->
  Docs.get_current_by_slug(workspace.id, slug)
end

thread_specs = [
  %{doc: "stack-overview", author: "bob", actor: "human",
    body: "Worth noting: keep an eye on pool utilization in the managed PG dashboard. If we ever start sitting near the cap during peak, that's the upgrade signal."},
  %{doc: "stack-overview", author: "alice", actor: "agent",
    body: "Good call. Worth adding to architecture-decisions when we make the call to upgrade."},
  %{doc: "stack-overview", author: "carol", actor: "human",
    body: "Reading this on my first day — super helpful, thanks."},
  %{doc: "oncall-runbook", author: "alice", actor: "human",
    body: "Reminder: the page button in Sentry now defaults to ALL responders. Be specific about who you're paging."},
  %{doc: "oncall-runbook", author: "bob", actor: "agent",
    body: "Added an escalation section in v2 and tightened the SLA in v3 — see history."},
  %{doc: "deploy-guide", author: "carol", actor: "human",
    body: "Does the pre-flight need to include mix dialyzer? Or is that overkill for v0?"}
]

Enum.each(thread_specs, fn spec ->
  doc = current.(spec.doc)
  author = users_by_username[spec.author]

  exists? =
    Repo.exists?(
      from m in Aveline.Comments.Comment,
        where:
          m.doc_id == ^doc.id and
            m.actor_user_id == ^author.id and
            m.body == ^spec.body and
            is_nil(m.deleted_at) and
            not m.superseded
    )

  unless exists? do
    {:ok, _} =
      Comments.create_comment(%{
        "doc_id" => doc.id,
        "body" => spec.body,
        "actor_user_id" => author.id,
        "actor_type" => spec.actor
      })
  end
end)

# ===== Demo activity =====
# A handful of kudos, reads, pin toggles, and a resolve so the History
# tab has something to show on first load. Each goes through the normal
# context fn → emits an event → renders in /activity.

# Kudos: everyone gives kudos to a doc someone else wrote.
kudos_specs = [
  {"alice", "oncall-runbook"},
  {"alice", "deploy-guide"},
  {"bob", "stack-overview"},
  {"bob", "architecture-decisions"},
  {"carol", "stack-overview"},
  {"carol", "local-dev-setup"},
  {"carol", "oncall-runbook"}
]

Enum.each(kudos_specs, fn {username, slug} ->
  giver = Map.fetch!(users_by_username, username)
  doc = current.(slug)

  if doc && doc.owner_id != giver.id do
    # Idempotent: only the first toggle counts as "given"; reseeding
    # without reset would toggle off, so guard with given_by?.
    unless Kudos.given_by?(doc.base_doc_id, giver.id) do
      {:ok, _} = Kudos.toggle(workspace.id, doc.base_doc_id, giver.id)
    end
  end
end)

# Doc views — distribute across users so the popularity sort isn't flat.
# Dedup window prevents duplicates from re-seeding without reset.
view_specs = [
  {"alice", "deploy-guide"},
  {"alice", "oncall-runbook"},
  {"alice", "sentry-tips"},
  {"bob", "architecture-decisions"},
  {"bob", "stack-overview"},
  {"bob", "local-dev-setup"},
  {"carol", "stack-overview"},
  {"carol", "local-dev-setup"},
  {"carol", "architecture-decisions"},
  {"carol", "oncall-runbook"},
  {"carol", "deploy-guide"}
]

Enum.each(view_specs, fn {username, slug} ->
  user = Map.fetch!(users_by_username, username)
  doc = current.(slug)
  if doc, do: DocViews.record(workspace.id, doc.base_doc_id, user.id, "human")
end)

# Home-page pin slots: a deliberate front page, in a deliberate order.
# (Also seeds doc_pinned events for the Activity tab.)
[
  {1, "onboarding-story"},
  {2, "stack-overview"},
  {3, "architecture-decisions"},
  {4, "oncall-runbook"},
  {5, "deploy-guide"}
]
|> Enum.each(fn {slot, slug} ->
  with %{pin_slot: nil} = doc <- current.(slug) do
    {:ok, _} = Docs.pin(doc, slot, bob.id)
  end
end)

# Resolve one of the open comment threads to seed a comment_resolved event.
case Repo.one(
       from c in Aveline.Comments.Comment,
         join: d in Aveline.Docs.Doc,
         on: d.id == c.doc_id,
         where:
           d.slug == "stack-overview" and
             c.body == "Worth noting: keep an eye on pool utilization in the managed PG dashboard. If we ever start sitting near the cap during peak, that's the upgrade signal." and
             is_nil(c.resolved_at) and is_nil(c.deleted_at) and not c.superseded,
         limit: 1
     ) do
  nil -> :ok
  c -> {:ok, _} = Comments.resolve_comment(c, alice.id)
end

# ===== Comment state showcase =====
# A full lifecycle on architecture-decisions so the doc page opens with
# every comment state already represented: open thread with a human +
# agent reply, an edited comment, a thread resolved via the agent's
# disposition reply on a new doc version, and a user-deleted thread.
# Hits enough states that the Open / All filter both have something
# different to show and the version switcher's time-travel renders
# meaningfully (v1 has the question open, v2 has it resolved).
arch = current.("architecture-decisions")

if arch && arch.version_number == 1 do
  # Anchor blocks: the two paragraph blocks (index 1 and 3).
  block_with_c1 = Enum.at(arch.blocks, 1)
  block_with_c2 = Enum.at(arch.blocks, 3)

  # c1 — alice (human) asks for a diagram, anchored to block 1.
  {:ok, c1} =
    Comments.create_comment(%{
      "doc_id" => arch.id,
      "block_id" => block_with_c1["id"],
      "body" => "Could we add a diagram here?",
      "actor_user_id" => alice.id,
      "actor_type" => "human"
    })

  # bob replies to c1.
  {:ok, _c1_reply} =
    Comments.create_comment(%{
      "doc_id" => arch.id,
      "parent_comment_id" => c1.base_comment_id,
      "block_id" => block_with_c1["id"],
      "body" => "+1, even a simple ASCII flow would help.",
      "actor_user_id" => bob.id,
      "actor_type" => "human"
    })

  # c2 — carol (human) on the other paragraph, still open at end of seed.
  {:ok, c2} =
    Comments.create_comment(%{
      "doc_id" => arch.id,
      "block_id" => block_with_c2["id"],
      "body" => "Is this still relevant after the LV refactor?",
      "actor_user_id" => carol.id,
      "actor_type" => "human"
    })

  # alice (as agent this time) replies to c2.
  {:ok, _c2_reply} =
    Comments.create_comment(%{
      "doc_id" => arch.id,
      "parent_comment_id" => c2.base_comment_id,
      "block_id" => block_with_c2["id"],
      "body" =>
        "Yes, the underlying decisions still hold. The LV refactor only touched rendering, not the architecture.",
      "actor_user_id" => alice.id,
      "actor_type" => "agent"
    })

  # c3 — bob's doc-level question, which he'll later delete.
  {:ok, c3} =
    Comments.create_comment(%{
      "doc_id" => arch.id,
      "body" => "Should we link to deploy-guide for the operational implications?",
      "actor_user_id" => bob.id,
      "actor_type" => "human"
    })

  # alice edits c1 to add a clarifying suffix. Creates a v2 row of c1;
  # the prior row is superseded.
  c1_current = Comments.get_current_by_base(c1.base_comment_id)

  {:ok, _c1_v2} =
    Comments.edit_comment_body(
      c1_current,
      "Could we add a diagram here? Even a simple ASCII flow would do.",
      alice.id
    )

  # Ship arch v2: modify the block c1 anchors to (adding a placeholder
  # diagram note) and resolve c1 via the disposition reply path. c2's
  # block is untouched, so no disposition is required.
  new_content =
    (block_with_c1["content"] || []) ++
      [
        %{
          "text" =>
            " (Diagram placeholder: replace with a real ASCII flow next pass.)",
          "marks" => ["italic"]
        }
      ]

  ops = [
    %{
      "op" => "modify_block",
      "id" => block_with_c1["id"],
      "patch" => %{"content" => new_content},
      "metadata" => %{"diff_intent" => "address the diagram request"}
    }
  ]

  {:ok, _arch_v2} =
    Docs.apply_ops(arch, ops, %{actor_user_id: alice.id, actor_type: "agent"},
      intent: "Address the request for a diagram (placeholder for now)",
      dispositions: [
        %{
          "comment_id" => c1.base_comment_id,
          "action" => "resolve",
          "reply" =>
            "Added a placeholder. Will fill in a real diagram on the next pass."
        }
      ]
    )

  # bob deletes his doc-level c3 (decided to file an issue instead).
  c3_current = Comments.get_current_by_base(c3.base_comment_id)
  {:ok, _} = Comments.soft_delete_comment(c3_current, bob.id)
end

# ===== Summary =====

IO.puts("")
# ===== Data source + charts dashboard =====
# The dev DB charts itself: the seeded data source points back at
# aveline_dev, so the dashboard doc renders live numbers about the
# seed data with zero external setup.

self_template =
  "postgres://#{System.get_env("PGUSER") || "postgres"}:<password>@#{System.get_env("PGHOST") || "localhost"}/#{System.get_env("PGDATABASE") || "aveline_dev"}"

self_password = System.get_env("PGPASSWORD") || "postgres"

if is_nil(Aveline.DataSources.get_current_by_name(workspace.id, "aveline-self")) do
  {:ok, _ds} =
    Aveline.DataSources.create(workspace.id, "aveline-self", self_template, self_password, alice.id)
end

chart = fn query, viz ->
  %{"type" => "chart", "source" => "aveline-self", "query" => query, "viz" => viz}
end

if is_nil(Docs.get_current_by_slug(workspace.id, "metrics-dashboard")) do
  {:ok, _dash} =
    Docs.create_doc(%{
      workspace_id: workspace.id,
      owner_id: alice.id,
      actor_user_id: alice.id,
      actor_type: "agent",
      slug: "metrics-dashboard",
      title: "Metrics dashboard",
      summary: "Live charts over this very database: docs per day, versions by actor, comment volume.",
      tags: ["product"],
      intent: "seed a chart-block showcase against the dev DB itself",
      blocks: [
        para.([
          t.("Every chart below runs a live read-only query against this workspace's own database through the "),
          b.("aveline-self", ["code"]),
          t.(" data source. Edit the SQL with ordinary apply-ops.")
        ]),
        heading.(2, "Doc versions per day"),
        chart.(
          "SELECT inserted_at::date AS day, count(*) AS versions FROM docs GROUP BY 1 ORDER BY 1",
          %{"type" => "line", "x" => "day", "y" => "versions"}
        ),
        heading.(2, "Versions by actor type"),
        chart.(
          "SELECT actor_type, count(*) AS versions FROM docs GROUP BY 1 ORDER BY 2 DESC",
          %{"type" => "bar", "x" => "actor_type", "y" => "versions"}
        ),
        heading.(2, "Most-versioned docs (table)"),
        chart.(
          "SELECT title, max(version_number) AS versions FROM docs WHERE NOT superseded GROUP BY title ORDER BY 2 DESC LIMIT 5",
          %{"type" => "table"}
        ),
        heading.(2, "A broken query (error state showcase)"),
        chart.(
          "SELECT nope FROM does_not_exist",
          %{"type" => "table"}
        )
      ]
    })
end

# ===== Query catalog + workspace-source charts =====
# The catalog layer: named queries built on aveline-self, composed in
# the DuckDB engine through the built-in `workspace` source. Charts here
# point at `workspace` and speak the analytics dialect (regressions,
# window functions) over the catalog — things the raw source can't do in
# one query. Idempotent: skip any query that already exists.

catalog_specs = [
  # raw leaves over the dev DB
  {"docs_per_day", "aveline-self",
   "SELECT inserted_at::date AS day, count(*) AS n FROM docs WHERE NOT superseded GROUP BY 1 ORDER BY 1"},
  {"comments_per_day", "aveline-self",
   "SELECT inserted_at::date AS day, count(*) AS n FROM doc_comments GROUP BY 1 ORDER BY 1"},
  # derived: a cross-query join (docs vs comments per day) — neither
  # leaf can answer this alone; the engine joins them.
  {"activity_per_day", nil,
   "SELECT d.day, d.n AS docs, coalesce(c.n, 0) AS comments FROM docs_per_day d LEFT JOIN comments_per_day c USING (day) ORDER BY d.day"},
  # derived on derived (a chain): a rolling trend the source dialect
  # can't express — window over the joined series.
  {"activity_trend", nil,
   "SELECT day, docs, avg(docs) OVER (ORDER BY day ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS docs_ma3, regr_slope(docs, epoch(day::timestamp)) OVER () AS slope FROM activity_per_day ORDER BY day"}
]

Enum.each(catalog_specs, fn {name, source, sql} ->
  if is_nil(Aveline.DataSources.Queries.get_current_by_name(workspace.id, name)) do
    attrs = %{name: name, sql: sql} |> then(fn a -> if source, do: Map.put(a, :source, source), else: a end)
    {:ok, _} = Aveline.DataSources.Queries.create(workspace.id, attrs, alice.id)
  end
end)

wchart = fn query, viz ->
  %{"type" => "chart", "source" => "workspace", "query" => query, "viz" => viz}
end

if is_nil(Docs.get_current_by_slug(workspace.id, "catalog-dashboard")) do
  {:ok, _dash} =
    Docs.create_doc(%{
      workspace_id: workspace.id,
      owner_id: alice.id,
      actor_user_id: alice.id,
      actor_type: "agent",
      slug: "catalog-dashboard",
      title: "Catalog dashboard (workspace source)",
      summary: "Charts over the query catalog: a cross-query join and a rolling trend + regression, composed in the analytics engine.",
      tags: ["product"],
      intent: "seed a workspace-source chart showcase over the query catalog",
      blocks: [
        para.([
          t.("These charts point at the built-in "),
          b.("workspace", ["code"]),
          t.(" source. Their SQL is the analytics dialect (DuckDB) over catalog queries — "),
          b.("activity_per_day", ["code"]),
          t.(" joins two raw queries, "),
          b.("activity_trend", ["code"]),
          t.(" chains on top with a moving average and a regression slope the source can't express.")
        ]),
        heading.(2, "Docs vs comments per day (cross-query join)"),
        wchart.(
          "SELECT day, docs, comments FROM activity_per_day ORDER BY day",
          %{"type" => "combo", "x" => "day", "series" => [%{"y" => "docs", "type" => "line"}, %{"y" => "comments", "type" => "bar"}]}
        ),
        heading.(2, "Docs per day with 3-day moving average (chained derived query)"),
        wchart.(
          "SELECT day, docs, docs_ma3 FROM activity_trend ORDER BY day",
          %{"type" => "combo", "x" => "day", "series" => [%{"y" => "docs", "type" => "bar"}, %{"y" => "docs_ma3", "type" => "line"}]}
        ),
        heading.(2, "Docs per day with a fitted regression line"),
        para.([
          t.("The "),
          b.("fit", ["code"]),
          t.(" series is the least-squares line, computed in SQL: "),
          b.("regr_slope(y, x) OVER () * x + regr_intercept(y, x) OVER ()", ["code"]),
          t.(". Plotted as a line over the actual bars. The source dialect can't do this; the engine can.")
        ]),
        wchart.(
          "SELECT day, docs, regr_slope(docs, epoch(day::timestamp)) OVER () * epoch(day::timestamp) + regr_intercept(docs, epoch(day::timestamp)) OVER () AS fit FROM activity_per_day ORDER BY day",
          %{"type" => "combo", "x" => "day", "series" => [%{"y" => "docs", "type" => "bar"}, %{"y" => "fit", "type" => "line"}]}
        ),
        heading.(2, "7-day forecast (regression extended past the data)"),
        para.([
          t.("The fit line evaluated at future dates the data doesn't have: "),
          b.("generate_series", ["code"]),
          t.(" fabricates the next 7 days, and the regression formula projects onto them. "),
          b.("actual", ["code"]),
          t.(" stops at the last real day; "),
          b.("forecast", ["code"]),
          t.(" runs 7 days past it. (Linear extrapolation of a steep toy trend dives negative fast — that's the math, not a bug.)")
        ]),
        wchart.(
          "WITH pts AS (SELECT day, docs FROM activity_per_day), model AS (SELECT regr_slope(docs, epoch(day::timestamp)) AS m, regr_intercept(docs, epoch(day::timestamp)) AS b FROM pts), axis AS (SELECT unnest(generate_series((SELECT min(day) FROM pts), (SELECT max(day) FROM pts) + INTERVAL 7 DAY, INTERVAL 1 DAY))::date AS day) SELECT a.day, p.docs AS actual, round(m.m * epoch(a.day::timestamp) + m.b, 2) AS forecast FROM axis a CROSS JOIN model m LEFT JOIN pts p ON p.day = a.day ORDER BY a.day",
          %{"type" => "combo", "x" => "day", "series" => [%{"y" => "actual", "type" => "bar"}, %{"y" => "forecast", "type" => "line"}]}
        ),
        heading.(2, "Ad-hoc: regression slope over the catalog (table)"),
        wchart.(
          "SELECT round(regr_slope(docs, epoch(day::timestamp)) * 86400, 4) AS docs_per_day_trend FROM activity_per_day",
          %{"type" => "table"}
        )
      ]
    })
end

# ===== Tickets (for grouping / sub-grouping demos) =====
# Real tickets tagged status:* + ticket:* — the tickets view groups by
# status and sub-groups by ticket type, so the two-level layout has
# something to show.

ticket_specs = [
  {"Sprite flicker on scanline 240", "ppu", "bug", "backlog"},
  {"Audio pops when a channel restarts", "apu", "bug", "todo"},
  {"Save-state slots in the UI", "ui", "feature", "todo"},
  {"Mapper 4 IRQ timing off by a cycle", "mappers", "bug", "in-progress"},
  {"Fast-forward hotkey", "ui", "feature", "in-progress"},
  {"Controller remapping screen", "ui", "feature", "backlog"},
  {"Palette emphasis bits ignored", "ppu", "bug", "done"},
  {"Cartridge header parser", "core", "feature", "done"}
]

Enum.each(ticket_specs, fn {title, topic, type, status} ->
  slug = title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

  if is_nil(Docs.get_current_by_slug(workspace.id, slug)) do
    # Topic tags are created on the fly; ensure they exist.
    if is_nil(Tags.get(workspace.id, topic)) do
      {:ok, _} = Tags.create(workspace.id, topic, "#{topic} work.", alice.id)
    end

    {:ok, _} =
      Docs.create_doc(%{
        workspace_id: workspace.id,
        owner_id: Enum.random([alice, bob, carol]).id,
        actor_user_id: alice.id,
        actor_type: "agent",
        slug: slug,
        title: title,
        summary: "#{type} in #{topic}.",
        tags: ["ticket", "ticket:#{type}", "status:#{status}", topic],
        blocks: [para.([t.(title)])],
        intent: "seed a ticket for grouping demos"
      })
  end
end)

# ===== Views =====
# The kanban-feature view: what the old board doc used to be, as a
# first-class view. Pinned so it shows in the sidebar.

if is_nil(Aveline.Views.get_current_by_name(workspace.id, "kanban-feature")) do
  {:ok, seeded_view} =
    Aveline.Views.create(
      workspace.id,
      "kanban-feature",
      "All work on the kanban feature, grouped by status. Move a card by retagging.",
      %{"tags" => ["kanban-feature"], "group_by" => "status"},
      alice.id
    )

  {:ok, _} = Aveline.Views.set_pinned(seeded_view, true)
end

if is_nil(Aveline.Views.get_current_by_name(workspace.id, "tickets")) do
  {:ok, tv} =
    Aveline.Views.create(
      workspace.id,
      "tickets",
      "All work, grouped by status and sub-grouped by ticket type. Move a card by retagging.",
      %{"tags" => ["ticket"], "group_by" => "status", "sub_group_by" => "ticket"},
      alice.id
    )

  {:ok, _} = Aveline.Views.set_pinned(tv, true)
end

# An UNPINNED view: reachable from the title switcher but absent from
# the sidebar — the two placements demoed side by side.
if is_nil(Aveline.Views.get_current_by_name(workspace.id, "runbooks")) do
  {:ok, _} =
    Aveline.Views.create(
      workspace.id,
      "runbooks",
      "Operational docs only. Unpinned on purpose: switcher-only.",
      %{"tags" => ["runbook"]},
      alice.id
    )
end

IO.puts("=== Local seed complete ===")
IO.puts("Workspace: #{workspace.slug} (Local Pod)")
IO.puts("")
IO.puts("Users + tokens:")

Enum.each(users, fn {spec, _} ->
  IO.puts("  #{String.pad_trailing(spec.username, 6)} #{spec.token}")
end)

IO.puts("")
IO.puts("Docs: #{length(doc_specs)} + onboarding-story (doc_link chain); stack-overview at v2, oncall-runbook at v3, architecture-decisions at v2 w/ showcase")
IO.puts("Comments: open + resolved + edited + deleted showcased on architecture-decisions; basic threads on three other docs.")
events_count = Repo.aggregate(Aveline.Events.Event, :count, :id)
IO.puts("Activity events: #{events_count} (all action types covered)")
IO.puts("")
