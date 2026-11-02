defmodule Aveline.Workspaces.Templates.AutonomousDev do
  @moduledoc """
  A team whose agents do most of the building. A working loop on day one:
  search before you file, a ticket for every piece of work, a plan on the
  ticket, a review by a fresh agent, write it down as work moves. Tags and
  three pinned boards to carry it, and the words a person uses to hand
  work to their agent.

  Lifted from the first workspace with months of real use behind it and
  rewritten generically: no branch names, test commands or deploys.
  """

  import Aveline.Blocks.Builder
  alias Aveline.Workspaces.Templates.Frame

  def name, do: "autonomous-dev"
  def title, do: "Autonomous dev"

  def summary,
    do:
      "A working loop on day one: tickets by status, ideas by stage, feedback, three pinned boards, and how to hand work to your agent."

  def recommended?, do: true

  @doc "Tags: `{slug, description, color | nil, sort_key | nil}`."
  def tags do
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
  Boards, pinned to the sidebar: `{name, description, config}`. A board
  groups by a tag family, so each `group_by` names one the tag set
  defines; feedback has no family of its own and is a plain list.
  """
  def views do
    [
      {"tickets", "All work, grouped by status. Check here before filing something that may already exist.",
       %{"tags" => ["ticket"], "group_by" => "status", "layout" => "board"}},
      {"ideas", "Pitches and where each has got to, from draft to approved.",
       %{"tags" => ["idea"], "group_by" => "stage", "layout" => "board"}},
      {"feedback", "Everything that came from someone outside the team, newest first.",
       %{"tags" => ["feedback"], "layout" => "list"}}
    ]
  end

  @doc "Docs: `{slug, title, summary, tags, blocks}`. One template, for the doc a team writes before building."
  def docs do
    [
      {"idea-template", "Idea template",
       "The sections a one-page pitch should have. Copy this structure, then tag it idea and stage:draft.",
       ["template", "idea"], idea_template_blocks()}
    ]
  end

  def orientation_blocks do
    Frame.scaffold(how_we_work()) ++ handing_work_over() ++ tag_section()
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

  defp handing_work_over do
    [
      h2("How we hand work to an agent"),
      para(
        t(
          "Three words a person says to their agent. Agents: follow these here; a person can always ask for something different."
        )
      ),
      ul([
        [
          b("BG. "),
          t(
            "Do the whole thing and bring back the finished work to look at. One report at the end. No questions on the way unless a guess would be unsafe. The default for most work."
          )
        ],
        [
          b("FG. "),
          t(
            "Do it live while they watch and steer. Change fast, show them as you go, and finish properly when they say ship."
          )
        ],
        [b("File it. "), t("Write the idea down as a doc, build nothing.")]
      ]),
      para(t("BG is the recommendation; FG is for things they need to see to judge."))
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
end
