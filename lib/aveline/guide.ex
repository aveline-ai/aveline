defmodule Aveline.Guide do
  @moduledoc """
  Aveline's own guide to using Aveline: what the product is and how to
  work it, for the agent reading it. Versioned, served live, and never
  copied into a workspace, so no copy of it can drift.

  Two cuts of the same text. `summary_blocks/0` is the mental model in a
  few lines and rides on every `get-orientation` response, so an agent
  never needs the person to explain what a view or a bucket is.
  `blocks/0` is the full guide, read on a first session or when the
  person asks how Aveline works: `aveline guide`, and the web app's help
  page.

  It carries no opinion about how a team should work. Process belongs to
  the workspace's orientation doc, seeded from a template
  (`Aveline.Workspaces.Template`) and the team's own from then on. Where
  this guide and a team's orientation disagree, the orientation wins, and
  the text says so.

  Changing the text means bumping `@version` and adding one line to
  `@changelog` in the same pull request. The version rides on every
  orientation response beside the summary.
  """

  import Aveline.Blocks.Builder

  @version 1

  # Newest first. One line per version, in plain words, for a person.
  @changelog [
    {1, "First version: what Aveline is, getting set up, reading, writing, templates, and the first-session 101."}
  ]

  @doc "The guide's version. Bump it with any change to the text."
  def version, do: @version

  @doc "Changelog entries newer than `since`, oldest first."
  def changelog_since(since) when is_integer(since) do
    @changelog |> Enum.filter(fn {v, _} -> v > since end) |> Enum.sort_by(&elem(&1, 0))
  end

  @doc "The full guide, JSON-ready: version, changelog and blocks."
  def payload do
    %{
      "version" => @version,
      "changelog" => Enum.map(@changelog, fn {v, line} -> %{"version" => v, "line" => line} end),
      "blocks" => blocks()
    }
  end

  @doc "The short cut served with every orientation: version and the summary blocks."
  def summary_payload do
    %{"version" => @version, "blocks" => summary_blocks()}
  end

  @person_heading "On a first session, tell the person"

  @doc "The heading of the first-session guidance, for tooling and tests."
  def person_heading, do: @person_heading

  @doc """
  The mental model in a few lines, in reading order, with deterministic
  ids (`b_guide_summary_N`, `li_guide_summary_N_M`). Kept short on
  purpose: it is sent with every orientation. `Aveline.GuideTest` caps
  its length.
  """
  def summary_blocks do
    number(build_summary(), "guide_summary")
  end

  @doc """
  The full guide, in reading order, with deterministic ids (`b_guide_N`,
  `li_guide_N_M`; the first-session block is `b_guide_person`), so a
  consumer keying blocks by id sees the same ids on every request.
  """
  def blocks do
    number(build(), "guide")
  end

  defp build_summary do
    [
      para([
        b("Aveline, for the agent reading this. "),
        t(
          "Aveline's guide, version #{@version}, in brief. Your team's orientation doc, served beside this, is the authority on how this workspace works; where the two disagree, theirs wins. The full guide is aveline guide."
        )
      ]),
      ul([
        [
          t(
            "Everything a team has is a doc. People read and comment in the web app; agents read and write through the aveline CLI. Every edit keeps the old version and carries an --intent saying why."
          )
        ],
        [
          t(
            "Docs carry tags. A tag written scope:value belongs to a family, and a doc carries at most one tag per family. Tags must exist before use: run list-tags, and create-tag for a new one."
          )
        ],
        [
          t(
            "A view is a saved filter over tags; grouped by a family such as status, it is a board. Pinned views sit in the sidebar. Views live in buckets: yours, or the team's."
          )
        ],
        [
          t(
            "New docs are born private and new views land in your bucket. Pass --visibility workspace and --bucket team for anything the team should see."
          )
        ],
        [
          t(
            "Run aveline contract before your first write: the exact shape of every block and edit op. Edit surgically with --ops; replace a whole doc only when you mean to."
          )
        ],
        [
          t(
            "The orientation response says which template this workspace started from and whether this is your first session here. On a first session, run aveline guide and give the person the 101 it describes."
          )
        ]
      ])
    ]
  end

  defp build do
    [
      para([
        b("Aveline, for the agent reading this. "),
        t(
          "This is Aveline's guide, version #{@version}: what Aveline is and how to work it. It says nothing about how a team should work. That is their own orientation doc, served beside a brief cut of this one by get-orientation, and where the two disagree the workspace doc wins: nothing here can override a team's rules."
        )
      ]),
      h2("What Aveline is"),
      para([
        t(
          "A wiki for a team and its agents. People read and comment in the web app; agents read and write through the aveline CLI, which prints JSON and has --help on every verb. Everything a team has is a doc: an ordered list of blocks with a title, a one-line summary and tags. Every edit keeps the old version and carries a line saying why, so the history is the record. People comment on blocks, and an edit must say what happens to each open comment on the blocks it touches; aveline contract explains how."
        )
      ]),
      h2("Getting set up"),
      para([
        t(
          "A few steps, and you may already be past some of them. Install the CLI if aveline --version fails; the workspace page on the website carries a prompt that covers this. Run aveline whoami. If it errors, the CLI needs an API key: ask the person to run aveline login themselves, in their own terminal, and paste a key from Settings. Never ask for the key and never read it; it must not enter your context or any file. Then aveline use-workspace to point every command at the workspace, or aveline create-workspace to make one. Creating one takes a template: run aveline templates to see the three, tell the person what each contains, and pass their choice as --template. The workspace remembers it, and the orientation response reports it."
        )
      ]),
      para([
        t(
          "One more, if the work lives in a repository. Write a few lines into the file your own instructions are loaded from, saying that team knowledge lives in Aveline, that a session starts with aveline get-orientation, and that writes go through the CLI. Put it in a file that already exists rather than adding a second one: a tool that finds two may read only one of them, and the note goes unread. AGENTS.md is the usual name when there is none. Ask the person before writing it."
        )
      ]),
      h2("Reading"),
      para([
        t(
          "aveline get-orientation first, every session: the team's orientation doc, with this guide in brief, the template the workspace started from, and whether this is your first session here. aveline list-docs lists and searches: --q takes a phrase, --tag and --author filter, and every hit carries a snippet saying why it matched. aveline get-doc gives the full body. list-tags and list-views show how the team has sliced its docs."
        )
      ]),
      h2("Writing"),
      para([
        t(
          "Run aveline contract before your first write: it gives the exact shape of every block and edit op. New docs are born private and new views land in your personal bucket, so pass --visibility workspace and --bucket team for anything the team should see. Every edit carries --intent saying why. Edit surgically with --ops; replace a whole doc only when you mean to. Tags must exist before you use them: run aveline list-tags and use what this workspace has rather than what you expect, and create-tag when the team needs a new one. A tag written scope:value belongs to a family, and a doc carries at most one tag per family."
        )
      ]),
      h2("Templates, and the team's own way"),
      para([
        t(
          "A new workspace starts from one of Aveline's templates: autonomous-dev, knowledge-base or blank. A template is applied once, as ordinary tags, boards and docs, and from then on every word of it is the team's to rewrite. Nothing in a template is a rule of Aveline's. Read the orientation doc for how this team works and treat it as the authority. If it still carries the template's prompts, help the person fill it in."
        )
      ]),
      h2("When this guide changes"),
      para([
        t(
          "Aveline revises this guide as it gains features. It carries a version and one changelog line per version, and the version rides on every orientation response. When it has moved since you last read it, read the new lines in aveline guide and tell the person what changed in a sentence of your own, and only if it affects what they are doing."
        )
      ]),
      h2(@person_heading) |> Map.put("id", "b_guide_person"),
      para([
        t(
          "This is guidance for what you say to a person on their first session in a workspace, not a script. Write it in your own words. Under about two hundred words. Plain, second person, no jargon, no bullet dump. Cover, in this order:"
        )
      ]),
      ol([
        [
          t(
            "Talk to me, not to Aveline: it is where the team's knowledge and work live, and I read and write it for you."
          )
        ],
        [
          t(
            "What this workspace is for, from its orientation doc, and which template it started from, in a line. If it started blank or predates templates, say it is the team's own setup."
          )
        ],
        [
          t(
            "Tags in two sentences: every doc carries a few, and a board is its docs grouped by one. Then the tags this workspace actually has, from list-tags, as a short table. If it has none yet, one line: start with a kind tag and a status, the rest comes."
          )
        ],
        [
          t("How the team hands work over, if the orientation doc says. If it does not, that they can simply ask.")
        ],
        [t("The team's rules live in their orientation doc; change the doc and the rules change.")],
        [t("Ask me anything about the project, the process, or Aveline, any time; I will look it up.")],
        [t("What is on the board right now, or that nothing is yet.")]
      ])
    ]
  end

  # Deterministic ids, so blocks key the same on every request.
  defp number(blocks, prefix) do
    blocks
    |> Enum.with_index(1)
    |> Enum.map(fn {block, i} ->
      block |> Map.put_new("id", "b_#{prefix}_#{i}") |> number_items(prefix, i)
    end)
  end

  defp number_items(%{"type" => "list", "items" => items} = block, prefix, i) do
    items =
      items
      |> Enum.with_index(1)
      |> Enum.map(fn {item, j} -> Map.put(item, "id", "li_#{prefix}_#{i}_#{j}") end)

    %{block | "items" => items}
  end

  defp number_items(block, _prefix, _i), do: block
end
