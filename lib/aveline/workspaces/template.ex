defmodule Aveline.Workspaces.Template do
  @moduledoc """
  The templates a new workspace starts from. Every workspace is created
  from exactly one, by name, and remembers which (`workspaces.template`).

  A template is ordinary data applied once: tags, pinned boards, a few
  docs, and the orientation doc's starting text. After creation it is the
  team's own, to reshape through their agents; Aveline never touches it
  again. Opinion about how a team should work lives here and nowhere
  else: Aveline's own guide (`Aveline.Guide`) describes the product and
  stays neutral.

  Each template is a module under `Aveline.Workspaces.Templates` exposing
  `name/0`, `title/0`, `summary/0`, `recommended?/0`, `tags/0`, `views/0`,
  `docs/0` and `orientation_blocks/0`. Register it in `@modules`, in the
  order the pickers show them.
  """

  alias Aveline.Workspaces.Templates

  @modules [Templates.AutonomousDev, Templates.KnowledgeBase, Templates.Blank]

  @doc "Template names, in display order."
  def names, do: Enum.map(@modules, & &1.name())

  @doc "Whether `name` is a template."
  def valid?(name) when is_binary(name), do: name in names()
  def valid?(_), do: false

  @doc "The template module for `name`, or nil."
  def module(name) when is_binary(name), do: Enum.find(@modules, &(&1.name() == name))
  def module(_), do: nil

  @doc "What a template would create, as the API shows it. Nil for an unknown name."
  def preview(name) do
    case module(name) do
      nil ->
        nil

      mod ->
        %{
          "name" => mod.name(),
          "title" => mod.title(),
          "summary" => mod.summary(),
          "recommended" => mod.recommended?(),
          "tags" =>
            Enum.map(mod.tags(), fn {slug, description, _color, _sort} ->
              %{"slug" => slug, "description" => description}
            end),
          "views" =>
            Enum.map(mod.views(), fn {view_name, description, config} ->
              %{"name" => view_name, "description" => description, "config" => config}
            end),
          "docs" =>
            Enum.map(mod.docs(), fn {slug, title, _summary, tags, _blocks} ->
              %{"slug" => slug, "title" => title, "tags" => tags}
            end),
          "orientation_blocks" => mod.orientation_blocks()
        }
    end
  end

  @doc "One line per template, for pickers: name, title, summary, recommended, counts."
  def list do
    Enum.map(@modules, fn mod ->
      %{
        "name" => mod.name(),
        "title" => mod.title(),
        "summary" => mod.summary(),
        "recommended" => mod.recommended?(),
        "tag_count" => length(mod.tags()),
        "view_count" => length(mod.views()),
        "doc_count" => length(mod.docs())
      }
    end)
  end

  # Convenience accessors by name, for the seeder and tests.
  def tags(name), do: module!(name).tags()
  def views(name), do: module!(name).views()
  def docs(name), do: module!(name).docs()
  def orientation_blocks(name), do: module!(name).orientation_blocks()

  defp module!(name) do
    module(name) || raise ArgumentError, "unknown workspace template: #{inspect(name)}"
  end
end
