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
  def tags(mode \\ :standard)

  def tags(:custom), do: []

  def tags(:standard) do
    [
      # Kinds: what is this doc?
      {"ticket", "A unit of work, scoped small enough to map to roughly one change.", nil, nil},
      {"idea",
       "A one-page pitch: what and why, before anything is built. Moves through stage; a ticket is cut from an approved one.",
       nil, nil},
      {"template", "A reusable structure. Copy its sections when writing that kind of doc.", nil, nil},

      # status: where a ticket is. Sort keys give lifecycle order while
      # keeping the cluster where "status" sorts alphabetically.
      {"status:backlog", "Captured, not started.", nil, "status:1"},
      {"status:next", "Committed, up next.", "#3b82f6", "status:2"},
      {"status:in-flight", "Being worked on now.", "#e09150", "status:3"},
      {"status:review", "Built, waiting on a review or a decision.", "#06b6d4", "status:4"},
      {"status:shipped", "Done and live.", "#22c55e", "status:5"},
      {"status:cancelled", "Decided not to do it. Kept as the record, with a line saying why.", "#ef4444", "status:6"},

      # stage: how far an idea has got.
      {"stage:draft", "Being written. Don't rely on it yet.", nil, "stage:1"},
      {"stage:in-review", "Review requested. Comments welcome.", "#e09150", "stage:2"},
      {"stage:approved", "Agreed. Tickets can be cut from it.", "#22c55e", "stage:3"},
      {"stage:cancelled", "Considered and declined. Kept as the record.", "#ef4444", "stage:4"},

      # ticket: what kind of ticket.
      {"ticket:bug", "Something is broken.", "#ef4444", "ticket:1"},
      {"ticket:feature", "Something new, or a change to what exists.", "#8b5cf6", "ticket:2"},
      {"ticket:ui", "How something looks or fits, rather than what it does.", "#3b82f6", "ticket:3"},
      {"ticket:refactor", "Changing how the code is arranged without changing what it does.", nil, "ticket:4"},

      # Where it came from. Additive: a ticket or an idea carries it too.
      {"feedback", "Came from someone outside the team. Quote them, and pair it with a from:<name> tag you create.",
       nil, nil}
    ]
  end

  @doc """
  The orientation doc a new workspace starts with.

  Both modes write the same frame: a line telling an agent to read this
  first, then three headings each with a prompt under it. `:custom` stops
  there, leaving the team an empty doc to write into. `:standard` fills
  "How we work" with a loop that works on day one, and names the tags it
  created.
  """
  def orientation_blocks(mode \\ :standard)

  def orientation_blocks(:custom), do: scaffold(:prompt)

  def orientation_blocks(:standard),
    do: scaffold(:filled) ++ how_we_work() ++ tag_section()

  defp scaffold(how_we_work) do
    [
      para(
        t(
          "Agent: read this before anything else. It explains what lives in this workspace and how the team works. It's a normal doc. When conventions change, update it (with intent) like any other doc."
        )
      ),
      h2("What this workspace is for"),
      para(t("(Fill in: one or two lines on what this team builds and what knowledge belongs here.)")),
      h2("Read these first"),
      para(t("(Link the docs every newcomer should read, in order. Agents: fetch each with get-doc.)")),
      h2("How we work")
    ] ++
      case how_we_work do
        :prompt ->
          [
            para(
              t(
                "(Fill in: how work moves here. What gets written down before building, who reviews it, what happens when something ships. Aveline has a standard starter if you would rather begin from one.)"
              )
            )
          ]

        :filled ->
          []
      end
  end

  defp how_we_work do
    [
      para(t("How work moves here. Change any of it: this is your doc, not Aveline's.")),
      ul([
        [
          b("Search before you file. "),
          t(
            "Two or three short searches on the topic's words first. An existing ticket, idea or decision may already cover it, and this is how duplicates and forgotten calls are caught."
          )
        ],
        [b("Every piece of work is a ticket. "), t("Nothing ships that is not on the board.")],
        [
          b("Plan on the ticket before building: "),
          t(
            "what it does now with file and line references, the change by layer, the tests, the docs, and any open question with the default you will take."
          )
        ],
        [
          b("Review by a fresh agent "),
          t(
            "with no memory of the build, read-only, findings only: one line each, a file and line, a concrete failure, most severe first. Findings go back to the builder rather than onto the pull request. Fix every real one or say why not, then say in a line what the review found. Words-only changes skip it."
          )
        ],
        [
          b("Write it down. "),
          t(
            "Retag as work moves, record the change on its ticket, and fix any doc the change made wrong in the same sitting."
          )
        ],
        [
          b("A project spanning several tickets "),
          t(
            "gets a tag of its own on each, a board filtered to that tag and grouped by status, and a one-page doc carrying only the project tag, so it has no status and sits above the columns."
          )
        ],
        [
          b("One status and one subtype per ticket. "),
          t("Cancel by retagging with a line saying why, never by deleting.")
        ]
      ])
    ]
  end

  defp tag_section do
    [
      h2("The tags we start with"),
      para(
        t(
          "A tag written as scope:value belongs to a family named by the part before the colon. A doc carries at most one tag from a family, and a board can only group by a family, which is what makes the boards below work. Add your own as you go: an area, a project, a from:<name> beside feedback."
        )
      ),
      ul([
        [b("Kind: "), code_t("ticket"), t(", "), code_t("idea"), t(", "), code_t("template"), t(".")],
        [
          b("Ticket subtype: "),
          code_t("ticket:bug"),
          t(", "),
          code_t("ticket:feature"),
          t(", "),
          code_t("ticket:ui"),
          t(", "),
          code_t("ticket:refactor"),
          t(".")
        ],
        [
          b("Ticket status: "),
          code_t("status:backlog"),
          t(" through "),
          code_t("status:shipped"),
          t(", plus "),
          code_t("status:cancelled"),
          t(". The tickets board's columns, in that order.")
        ],
        [
          b("Idea stage: "),
          code_t("stage:draft"),
          t(" through "),
          code_t("stage:approved"),
          t(", plus "),
          code_t("stage:cancelled"),
          t(".")
        ],
        [
          b("Where it came from: "),
          code_t("feedback"),
          t(", carried alongside a ticket or an idea rather than instead of one.")
        ]
      ]),
      para(
        t(
          "Three boards are pinned for you: tickets by status, ideas by stage, and everything tagged feedback. Make more with create-view."
        )
      )
    ]
  end

  @doc """
  Boards a new workspace starts with, pinned to the sidebar. `:custom`
  gets none, since it has no tags to filter on.

  Returns `{name, description, config}`. A board groups by a tag family,
  so each `group_by` here names one the tag set defines; feedback has no
  family of its own and is a plain list.
  """
  def views(mode \\ :standard)

  def views(:custom), do: []

  def views(:standard) do
    [
      {"tickets", "All work, grouped by status. Check here before filing something that may already exist.",
       %{"tags" => ["ticket"], "group_by" => "status", "layout" => "board"}},
      {"ideas", "Pitches and where each has got to, from draft to approved.",
       %{"tags" => ["idea"], "group_by" => "stage", "layout" => "board"}},
      {"feedback", "Everything that came from someone outside the team, newest first.",
       %{"tags" => ["feedback"], "layout" => "list"}}
    ]
  end

  @doc """
  Docs a new workspace starts with. `:custom` gets none, because an empty
  workspace is the point of it. `:standard` gets one template, for the
  kind of doc a team writes before building.
  """
  def docs(mode \\ :standard)

  def docs(:custom), do: []

  def docs(:standard) do
    [
      {"idea-template", "Idea template",
       "The sections a one-page pitch should have. Copy this structure, then tag it idea and stage:draft.",
       ["template", "idea"], idea_template_blocks()}
    ]
  end

  defp idea_template_blocks do
    [
      para(t("Copy these sections into a new doc tagged idea. One page: if it needs more, it is two ideas.")),
      h2("Problem"),
      para(t("(Who hurts, how much, how do we know. Link the feedback that evidences it.)")),
      h2("Opportunity"),
      para(t("(Why this is worth doing now. Size it honestly.)")),
      h2("Proposal"),
      para(t("(What we would build, at the level of what someone using it experiences.)")),
      h2("Success criteria"),
      para(t("(How we would know it worked. Numbers where you can.)")),
      h2("Open questions"),
      para(t("(What needs deciding before a ticket can be cut. Anchor comments here.)"))
    ]
  end

  # ===== tiny block builders =====

  defp t(text), do: %{"text" => text}
  defp code_t(text), do: %{"text" => text, "marks" => ["code"]}
  defp b(text), do: %{"text" => text, "marks" => ["bold"]}
  defp para(spans) when is_list(spans), do: %{"type" => "paragraph", "content" => spans}
  defp para(span), do: %{"type" => "paragraph", "content" => [span]}
  defp h2(text), do: %{"type" => "heading", "level" => 2, "text" => text}

  defp ul(items),
    do: %{"type" => "list", "ordered" => false, "items" => Enum.map(items, &%{"content" => &1})}
end
