defmodule Aveline.Workspaces.Templates.KnowledgeBase do
  @moduledoc """
  Durable team knowledge with work alongside it: product, architecture,
  runbook and oncall docs accumulate; feedback becomes a brief (what and
  why) becomes a tip (how) becomes tickets. The set Aveline seeded into
  every workspace before templates existed.
  """

  import Aveline.Blocks.Builder
  alias Aveline.Workspaces.Templates.Frame

  def name, do: "knowledge-base"
  def title, do: "Knowledge base"

  def summary,
    do:
      "Durable team knowledge first: product, architecture, briefs, tips, runbooks and oncall docs, with tickets and a status board alongside."

  def recommended?, do: false

  @doc "Tags: `{slug, description, color | nil, sort_key | nil}`."
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

      # status: where the work is.
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

  @doc "One pinned board: tickets by status."
  def views do
    [
      {"tickets", "All work, grouped by status.", %{"tags" => ["ticket"], "group_by" => "status", "layout" => "board"}}
    ]
  end

  @doc "Docs: `{slug, title, summary, tags, blocks}`."
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

  def orientation_blocks do
    Frame.scaffold([
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
          t(". The pinned "),
          code_t("tickets"),
          t(" board groups them by status. Move work forward by retagging; save more views with "),
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
        [t("Every doc gets a one-line summary and every edit gets an intent. That's what future agents read first.")]
      ])
    ])
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
end
