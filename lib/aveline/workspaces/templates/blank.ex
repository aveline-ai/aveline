defmodule Aveline.Workspaces.Templates.Blank do
  @moduledoc "The empty frame: an orientation doc with prompts, and nothing else."

  import Aveline.Blocks.Builder
  alias Aveline.Workspaces.Templates.Frame

  def name, do: "blank"
  def title, do: "Blank"

  def summary,
    do: "Just the orientation doc, with a prompt under each heading. You create every tag, board and doc yourself."

  def recommended?, do: false

  def tags, do: []
  def views, do: []
  def docs, do: []

  def orientation_blocks do
    Frame.scaffold([
      para(
        t(
          "(Fill in: how work moves here. What gets written down before building, who reviews it, what happens when something ships. Start by creating the tags you need with create-tag; a doc cannot carry a tag that does not exist yet. Aveline's other templates are a reference if you want one: aveline templates.)"
        )
      )
    ])
  end
end
