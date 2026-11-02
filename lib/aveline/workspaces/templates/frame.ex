defmodule Aveline.Workspaces.Templates.Frame do
  @moduledoc """
  The orientation frame every template writes: a line telling an agent to
  read this first, then "What this workspace is for", "Read these first"
  and "How we work". A template fills "How we work" with its own text, or
  leaves a prompt.
  """

  import Aveline.Blocks.Builder

  @doc "The frame, with `how_we_work` blocks under the third heading."
  def scaffold(how_we_work) when is_list(how_we_work) do
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
    ] ++ how_we_work
  end
end
