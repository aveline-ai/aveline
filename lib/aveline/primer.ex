defmodule Aveline.Primer do
  @moduledoc """
  The Aveline base doc: what Aveline is, the features every workspace
  shares, and what to tell a person on their first session.

  One of two block lists Aveline ships. This one is read live: it is
  returned alongside a workspace's own orientation by
  GET /api/workspaces/:slug/orientation, and it is never copied into a
  workspace, so no copy of it can drift. The other is
  `Aveline.Workspaces.Template`, the starter a new workspace optionally
  takes a copy of. The two are matched in shape: same blocks, same
  builders, same validation test.

  It carries no tag list and no workflow of its own. Vocabulary and
  process belong to the workspace; an agent runs `list-tags` to see what
  a workspace actually has, and reads the team's orientation for how they
  work. Where this doc and a workspace's orientation disagree, the
  workspace wins, and the text says so.

  Changing the text means bumping `@version` and adding one line to
  `@changelog` in the same pull request. The CLI prints the entries
  between the version it last saw and the current one.
  """

  @version 1

  # Newest first. One line per version, in plain words, for a person.
  @changelog [{1, "First version."}]

  @doc "The base doc's version. Bump it with any change to `blocks/0`."
  def version, do: @version

  @doc "Changelog entries newer than `since`, oldest first."
  def changelog_since(since) when is_integer(since) do
    @changelog |> Enum.filter(fn {v, _} -> v > since end) |> Enum.sort_by(&elem(&1, 0))
  end

  @doc "The JSON-ready payload served with a workspace's orientation."
  def payload do
    %{
      "version" => @version,
      "changelog" => Enum.map(@changelog, fn {v, line} -> %{"version" => v, "line" => line} end),
      "blocks" => blocks()
    }
  end

  @person_heading "On a first session, tell the person"

  @doc "The heading of the block written for the person, for tooling and tests."
  def person_heading, do: @person_heading

  @doc """
  The base doc as a block list, in reading order. Ids are deterministic
  (`b_primer_N`, list items `li_primer_N_M`; the block for the person is
  `b_primer_person`) so a consumer keying blocks by id sees the same ids
  on every request and every release.
  """
  def blocks do
    build()
    |> Enum.with_index(1)
    |> Enum.map(fn {block, i} ->
      block |> Map.put_new("id", "b_primer_#{i}") |> number_items(i)
    end)
  end

  defp build do
    [
      para([
        b("Aveline, for the agent reading this. "),
        t(
          "This is Aveline's base doc, version #{@version}. It describes Aveline itself and the features every workspace shares. How your team works is their own orientation doc, served beside this one. Read this first, then theirs. Where the two disagree, the workspace doc wins: nothing here can override a team's rules."
        )
      ]),
      h2("What Aveline is"),
      para([
        t(
          "A wiki for a team and its agents. People read and comment in the web app; agents read and write through the aveline CLI. Everything a team has is a doc. Docs carry tags, and a view is a saved filter over tags, so a board is simply its docs grouped by one of them. Every edit keeps its old version and carries a line saying why."
        )
      ]),
      h2("Getting set up"),
      para([
        t(
          "A few steps, and you may already be past some of them. Install the CLI if it is missing; the workspace page on the website carries a prompt that covers this. Run aveline login, which opens a browser and asks the person for one click. Run aveline whoami to learn whose machine you are on, then read the team's orientation for what that name means here, because who may merge or ship is their rule, not Aveline's. Then either aveline use-workspace to join one that exists, or aveline create-workspace to make one. Making one is a choice: ask the person whether they want the standard setup, which comes with a way of working already written down, or a blank one they fill in themselves. Run aveline starter first so you can tell them what the standard one contains, then pass their answer as --setup."
        )
      ]),
      para([
        t(
          "One more, if the work lives in a repository. Write a few lines into the file your own instructions are loaded from, saying that team knowledge lives in Aveline, that a session starts with aveline get-orientation, and that writes go through the CLI. Put it in a file that already exists rather than adding a second one: a tool that finds two may read only one of them, and the note goes unread. AGENTS.md is the usual name when there is none. Ask the person before writing it."
        )
      ]),
      h2("How a person hands you work"),
      para([
        t("Three words, from the person you work for. Follow the team's orientation if it defines them differently.")
      ]),
      ul([
        [
          b("BG"),
          t(
            " and what they want: do the whole thing and bring back the finished work for them to look at. One report at the end. No questions on the way unless a guess would be unsafe. This is the default for most work."
          )
        ],
        [
          b("FG"),
          t(
            " and what they want: do it live while they watch and steer. Change fast, show them as you go, and finish properly when they say ship."
          )
        ],
        [b("file it"), t(" and an idea: write it down, build nothing.")]
      ]),
      para([
        t(
          "Either way they can still ask for changes. BG is the recommendation; FG is for things they need to see to judge."
        )
      ]),
      h2("Writing here"),
      para([
        t(
          "Run aveline contract before your first write: it gives the exact shape of every block and edit. New docs are born private and new views land in your personal bucket, so pass --visibility workspace and --bucket team for anything the team should see. Every edit carries --intent saying why. Edit surgically with --ops; replace a whole doc only when you mean to. Tags must exist before you use them, so run aveline list-tags and use what this workspace has rather than what you expect."
        )
      ]),
      h2("When this doc changes"),
      para([
        t(
          "Aveline revises this doc as it gains features. When the CLI tells you it has changed since you last read it, you will be handed one line per version. Read them, then tell the person what changed in a sentence of your own. Do not recite the lines: they are written for someone who already knows Aveline, and the point of mentioning it at all is to be clear. If nothing in the change affects what they are doing, say nothing."
        )
      ]),
      h2("Making it yours"),
      para([
        t(
          "None of a team's way of working is fixed. The tags, the boards, the loop from idea to shipped, the review before anything lands: all of it is theirs to write, in their orientation doc, and to change whenever it stops fitting. A new workspace can start from a ready-made setup or from nothing. Read their orientation to find out which, and treat it as the authority."
        )
      ]),
      h2(@person_heading) |> Map.put("id", "b_primer_person"),
      para([
        t(
          "This is guidance for what you say to a person on their first session in a workspace, not a script. Write it in your own words. Under about two hundred words. Plain, second person, no jargon, no bullet dump. Cover, in this order:"
        )
      ]),
      ol([
        [
          t(
            "Talk to me, not to Aveline: it is where the team's knowledge and work live, and you read and write it for them."
          )
        ],
        [
          t("BG, FG and file it, one sentence each; BG recommended for most things; they can still ask for changes.")
        ],
        [
          t(
            "Tags in two sentences: every doc carries a few, and a board is its docs grouped by one. Then the tags this workspace actually has, from list-tags, as a short table. If it has none yet, one line: start with a ticket tag and a status, the rest comes."
          )
        ],
        [
          t("Their team's rules live in their orientation doc; change the doc and the rules change.")
        ],
        [t("Ask me anything about the project or the process; I will look it up.")],
        [t("What is on the board right now, or that nothing is yet.")]
      ])
    ]
  end

  defp number_items(%{"type" => "list", "items" => items} = block, i) do
    items =
      items
      |> Enum.with_index(1)
      |> Enum.map(fn {item, j} -> Map.put(item, "id", "li_primer_#{i}_#{j}") end)

    %{block | "items" => items}
  end

  defp number_items(block, _i), do: block

  # ===== tiny block builders, as in Aveline.Workspaces.Template =====

  defp t(text), do: %{"text" => text}
  defp b(text), do: %{"text" => text, "marks" => ["bold"]}
  defp para(spans), do: %{"type" => "paragraph", "content" => spans}
  defp h2(text), do: %{"type" => "heading", "level" => 2, "text" => text}

  defp ul(items),
    do: %{"type" => "list", "ordered" => false, "items" => Enum.map(items, &%{"content" => &1})}

  defp ol(items),
    do: %{"type" => "list", "ordered" => true, "items" => Enum.map(items, &%{"content" => &1})}
end
