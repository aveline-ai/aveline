defmodule Aveline.WorkspaceSetupModeTest do
  @moduledoc """
  A new workspace is furnished by the mode it was created with. Standard
  hands a team a loop that works on day one; Custom hands them the same
  frame with nothing filled in.
  """
  use Aveline.DataCase, async: false

  alias Aveline.{Docs, Fixtures, Tags, Views, Workspaces}
  alias Aveline.Workspaces.Template

  defp create(mode) do
    owner = Fixtures.user_fixture()
    slug = "ws-#{System.unique_integer([:positive])}"

    {:ok, ws} =
      Workspaces.create_workspace(%{
        "slug" => slug,
        "name" => "Mode #{slug}",
        "created_by_id" => owner.id,
        "setup" => mode
      })

    {ws, owner}
  end

  defp headings(blocks),
    do: for(%{"type" => "heading", "text" => text} <- blocks, do: text)

  test "standard furnishes the workspace" do
    {ws, _owner} = create("standard")

    # Named, not compared with the template: a slug dropped or misspelt
    # in the template must fail here rather than agree with itself.
    assert Enum.sort(Tags.list_slugs(ws.id)) ==
             Enum.sort([
               "ticket",
               "idea",
               "template",
               "ticket:bug",
               "ticket:feature",
               "ticket:ui",
               "ticket:refactor",
               "status:backlog",
               "status:next",
               "status:in-flight",
               "status:review",
               "status:shipped",
               "status:cancelled",
               "stage:draft",
               "stage:in-review",
               "stage:approved",
               "stage:cancelled",
               "feedback"
             ])

    assert Tags.list_scope_members(ws.id, "status") == [
             "status:backlog",
             "status:next",
             "status:in-flight",
             "status:review",
             "status:shipped",
             "status:cancelled"
           ]

    assert Tags.list_scope_members(ws.id, "stage") != []

    boards = ws.id |> Views.list_for_workspace() |> Enum.map(& &1.name) |> Enum.sort()
    assert boards == ["feedback", "ideas", "tickets"]
    assert Enum.all?(Views.list_pinned(ws.id), & &1.pinned)
    assert length(Views.list_pinned(ws.id)) == 3

    orientation = Docs.get_orientation(ws.id)
    assert "How we work" in headings(orientation.blocks)
    assert "The tags we start with" in headings(orientation.blocks)

    text = Jason.encode!(orientation.blocks)
    assert text =~ "Search before you file"
    assert text =~ "Review by a fresh agent"

    assert Docs.get_current_by_slug(ws.id, "idea-template")
  end

  test "custom writes the frame and nothing else" do
    {ws, _owner} = create("custom")

    assert Tags.list_slugs(ws.id) == []
    assert Views.list_for_workspace(ws.id) == []
    assert Docs.get_current_by_slug(ws.id, "idea-template") == nil

    orientation = Docs.get_orientation(ws.id)
    assert orientation, "every workspace gets an orientation doc, whichever mode"

    assert headings(orientation.blocks) == [
             "What this workspace is for",
             "Read these first",
             "How we work"
           ]

    text = Jason.encode!(orientation.blocks)
    assert text =~ "(Fill in: how work moves here"
    refute text =~ "Search before you file"
  end

  test "an unrecognised mode raises rather than furnishing silently" do
    owner = Fixtures.user_fixture()
    slug = "ws-#{System.unique_integer([:positive])}"

    # The API path rejects this in the Gleam handler, so anything that
    # reaches here came from code. Quietly picking a mode would hide it.
    assert_raise ArgumentError, ~r/unknown workspace setup mode/, fn ->
      Workspaces.create_workspace(%{
        "slug" => slug,
        "name" => "Odd #{slug}",
        "created_by_id" => owner.id,
        "setup" => "stnadard"
      })
    end
  end

  test "omitting the mode furnishes it, which is what every caller got before" do
    owner = Fixtures.user_fixture()
    slug = "ws-#{System.unique_integer([:positive])}"

    {:ok, ws} =
      Workspaces.create_workspace(%{
        "slug" => slug,
        "name" => "Plain #{slug}",
        "created_by_id" => owner.id
      })

    assert length(Tags.list_slugs(ws.id)) == 18
    assert length(Views.list_for_workspace(ws.id)) == 3
  end

  test "every seeded doc carries only tags the mode defines" do
    for mode <- [:standard, :custom] do
      defined = MapSet.new(Enum.map(Template.tags(mode), &elem(&1, 0)))

      for {_slug, _title, _summary, tags, _blocks} <- Template.docs(mode) do
        assert MapSet.subset?(MapSet.new(tags), defined),
               "#{mode}: a seeded doc carries a tag the mode does not create: #{inspect(tags)}"
      end
    end
  end

  test "every board groups by a family the mode creates" do
    for mode <- [:standard, :custom] do
      scopes =
        Template.tags(mode)
        |> Enum.map(fn {slug, _, _, _} -> Aveline.Tags.scope_of(slug) end)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      for {name, _desc, config} <- Template.views(mode), group = config["group_by"], group != nil do
        assert MapSet.member?(scopes, group),
               "#{mode}: board #{name} groups by #{group}, which the mode does not create"
      end
    end
  end

  test "every block the template writes is a valid block" do
    for mode <- [:standard, :custom] do
      for block <- Template.orientation_blocks(mode) do
        assert {:ok, _} = Aveline.Blocks.Block.validate(block, mint_id?: true),
               "#{mode}: orientation block did not validate: #{inspect(block)}"
      end

      for {slug, _title, _summary, _tags, blocks} <- Template.docs(mode),
          block <- blocks do
        assert {:ok, _} = Aveline.Blocks.Block.validate(block, mint_id?: true),
               "#{mode}: #{slug} block did not validate: #{inspect(block)}"
      end
    end
  end
end
