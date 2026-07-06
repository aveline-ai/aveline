defmodule Aveline.Workspaces.Template do
  @moduledoc """
  The recommended workspace setup, seeded into every new workspace:
  eight kind tags (what is this doc?), three scopes (mutually exclusive
  options), and an orientation doc whose conventions section is written
  for exactly this set.

  Deliberately one template, declaratively defined. Everything it seeds
  is ordinary data. Tags soft-delete and rename, the orientation doc is
  editable, so a team with its own conventions reshapes the workspace
  through their agents; a team without gets taught by good defaults.

  The pipeline the set encodes: feedback (evidence) becomes a brief
  (what and why) becomes a tip (how) becomes tickets (typed, statused,
  in views), while product, architecture, runbook, and oncall docs
  accumulate as durable knowledge. stage: covers editorial trust for
  any doc; no stage tag means live.
  """

  @doc "Baseline tags: `{slug, description, color | nil, sort_key | nil}`."
  def tags do
    [
      # Kinds: what is this doc? NULL sort_key = alphabetical.
      {"product", "What we're building and why: the product, its users, the strategy.", nil, nil},
      {"architecture", "How the system is built: stack, structure, and the technical why.", nil, nil},
      {"brief",
       "A product one-pager: the problem, the opportunity, the proposed direction. Pitch it, review it, get a verdict via stage.",
       nil, nil},
      {"tip",
       "A technical implementation plan (TIP). Pitch it, review it in comments, get a verdict via stage before building.",
       nil, nil},
      {"ticket", "A unit of work, scoped small enough to map to roughly one PR.", nil, nil},
      {"runbook", "Operational how-to: deploys, recovery, setup.", nil, nil},
      {"oncall",
       "Everything needed when paged: escalation paths, incident guides, known issues. Agents: load all of these when responding to an incident.",
       nil, nil},
      {"feedback", "Raw customer and user input, verbatim where possible.", nil, nil},
      {"template", "A reusable structure. Copy its sections when writing that kind of doc.", nil, nil},

      # status: where the work is. Sort keys give lifecycle order while
      # keeping the cluster where "status" sorts alphabetically.
      {"status:backlog", "Captured, not started.", nil, "status:1"},
      {"status:todo", "Next up.", "#3b82f6", "status:2"},
      {"status:in-progress", "Being worked on now.", "#e09150", "status:3"},
      {"status:done", "Shipped.", "#22c55e", "status:4"},
      {"status:cancelled", "Decided not to do it. Kept as the record.", "#ef4444", "status:5"},

      # stage: whether the doc is trustworthy. No stage tag means live.
      {"stage:draft", "Work in progress. Don't rely on this yet.", nil, "stage:1"},
      {"stage:in-review", "Review requested. Comments welcome.", "#e09150", "stage:2"},
      {"stage:approved", "Reviewed and approved.", "#22c55e", "stage:3"},
      {"stage:cancelled", "Considered and declined. Kept as the record.", "#ef4444", "stage:4"},

      # ticket: what kind of ticket.
      {"ticket:bug", "Something is broken.", "#ef4444", "ticket:1"},
      {"ticket:feature", "Something new.", "#8b5cf6", "ticket:2"}
    ]
  end

  @doc "Blocks for the seeded orientation doc."
  def orientation_blocks do
    [
      para(
        t(
          "Agent: read this before anything else. It explains what lives in this workspace and how the team works. It's a normal doc. When conventions change, update it (with intent) like any other doc."
        )
      ),
      h2("What this workspace is for"),
      para(t("(Fill in: one or two lines on what this team builds and what knowledge belongs here.)")),
      h2("Read these first"),
      para(
        t(
          "(Link the docs every newcomer should read, in order. Agents: fetch each with get-doc.)"
        )
      ),
      h2("How we organize knowledge"),
      ul([
        [
          t("Every doc usually carries one kind tag: "),
          code_t("product"),
          t(", "),
          code_t("architecture"),
          t(", "),
          code_t("brief"),
          t(", "),
          code_t("tip"),
          t(", "),
          code_t("ticket"),
          t(", "),
          code_t("runbook"),
          t(", "),
          code_t("oncall"),
          t(", or "),
          code_t("feedback"),
          t(
            ". Their descriptions say what belongs where. Create topic tags freely (a feature, a subsystem) and combine them with kinds."
          )
        ],
        [
          t("Work flows as tickets: "),
          code_t("ticket"),
          t(" plus one "),
          code_t("ticket:*"),
          t(" (bug or feature) plus one "),
          code_t("status:*"),
          t(". Views (Docs page and sidebar) are saved slices of the docs: group one by "),
          code_t("status"),
          t(" to track work through its stages. Move work forward by retagging; save views with "),
          code_t("create-view"),
          t(".")
        ],
        [
          t("Proposals get pitched: a "),
          code_t("brief"),
          t(" says what and why, a "),
          code_t("tip"),
          t(" says how. Write it as "),
          code_t("stage:draft"),
          t(", tag "),
          code_t("stage:in-review"),
          t(" when it wants eyes, and it ends "),
          code_t("stage:approved"),
          t(" or "),
          code_t("stage:cancelled"),
          t(". Cancelled ones stay: they record what we decided not to do.")
        ],
        [
          t("Not sure a doc is right yet? Tag it "),
          code_t("stage:draft"),
          t(". No stage tag means the doc is live and trustworthy. Agents: self-apply "),
          code_t("stage:draft"),
          t(" when you're not confident in what you wrote.")
        ],
        [
          t("Customer input lands as "),
          code_t("feedback"),
          t(" docs, verbatim. Acting on it means cutting a "),
          code_t("ticket"),
          t(".")
        ],
        [
          t("Writing a tip or a brief? Start from its "),
          code_t("template"),
          t(" doc and keep the sections.")
        ],
        [
          t("Every doc gets a one-line summary and every edit gets an intent. That's what future agents read first.")
        ]
      ])
    ]
  end

  @doc """
  Seeded template docs: `{slug, title, summary, tags, blocks}`. Scaffolds
  agents and humans copy when writing that kind of doc.
  """
  def docs do
    [
      {"tip-template", "TIP template",
       "The sections every technical implementation plan should have. Copy this structure.", ["template", "tip"],
       tip_template_blocks()},
      {"brief-template", "Product brief template",
       "The sections every product one-pager should have. Copy this structure.", ["template", "brief"],
       brief_template_blocks()}
    ]
  end

  defp tip_template_blocks do
    [
      para(
        t("Copy these sections into a new doc tagged tip. Keep it tight: a TIP should be readable in five minutes.")
      ),
      h2("Problem"),
      para(t("(What hurts today. Link the ticket or feedback that motivated this.)")),
      h2("Goals and non-goals"),
      para(t("(What this change must do, and what it deliberately won't.)")),
      h2("Proposed design"),
      para(t("(The how. Data model, API shape, migration path. Code sketches welcome.)")),
      h2("Alternatives considered"),
      para(t("(What else you looked at and why you passed. Saves the review round-trip.)")),
      h2("Risks and rollout"),
      para(t("(What could break, how we'd know, how it ships safely.)")),
      h2("Open questions"),
      para(t("(What you want reviewers to weigh in on. Anchor comments here.)"))
    ]
  end

  defp brief_template_blocks do
    [
      para(t("Copy these sections into a new doc tagged brief. One page: if it needs more, it's two briefs.")),
      h2("Problem"),
      para(t("(Who hurts, how much, how do we know. Link feedback docs as evidence.)")),
      h2("Opportunity"),
      para(t("(Why this is worth doing now. Size it honestly.)")),
      h2("Proposal"),
      para(t("(What we'd build, at the level of what the user experiences.)")),
      h2("Success criteria"),
      para(t("(How we'll know it worked. Numbers where possible.)")),
      h2("Open questions"),
      para(t("(What needs a decision before a TIP makes sense.)"))
    ]
  end

  # ===== tiny block builders =====

  defp t(text), do: %{"text" => text}
  defp code_t(text), do: %{"text" => text, "marks" => ["code"]}
  defp para(span), do: %{"type" => "paragraph", "content" => [span]}
  defp h2(text), do: %{"type" => "heading", "level" => 2, "text" => text}

  defp ul(items),
    do: %{"type" => "list", "ordered" => false, "items" => Enum.map(items, &%{"content" => &1})}
end
