defmodule Aveline.WorkspaceTemplateTest do
  @moduledoc """
  A new workspace is furnished by the template it was created from, and
  remembers which. Every template must be internally consistent: its docs
  carry only tags it creates, its boards group by families it creates,
  and every block it writes is a valid block.
  """
  use Aveline.DataCase, async: false

  alias Aveline.{Docs, Fixtures, Tags, Views, Workspaces}
  alias Aveline.Workspaces.Template

  defp create(template) do
    owner = Fixtures.user_fixture()
    slug = "ws-#{System.unique_integer([:positive])}"

    {:ok, ws} =
      Workspaces.create_workspace(%{
        "slug" => slug,
        "name" => "Template #{slug}",
        "created_by_id" => owner.id,
        "template" => template
      })

    {ws, owner}
  end

  defp headings(blocks), do: for(%{"type" => "heading", "text" => text} <- blocks, do: text)

  test "the registry lists three templates, recommended first" do
    assert Template.names() == ["autonomous-dev", "knowledge-base", "blank"]
    assert [%{"name" => "autonomous-dev", "recommended" => true} | rest] = Template.list()
    refute Enum.any?(rest, & &1["recommended"])
    assert Template.valid?("blank")
    refute Template.valid?("standard")
    assert Template.preview("nope") == nil
  end

  test "autonomous-dev furnishes the workspace and remembers its template" do
    {ws, _owner} = create("autonomous-dev")
    assert ws.template == "autonomous-dev"

    # Named, not compared with the template: a slug dropped or misspelt
    # in the template must fail here rather than agree with itself.
    assert Enum.sort(Tags.list_slugs(ws.id)) ==
             Enum.sort(~w(ticket idea template ticket:bug ticket:feature ticket:ui ticket:refactor
                  status:backlog status:next status:in-flight status:review status:shipped status:cancelled
                  stage:draft stage:in-review stage:approved stage:cancelled feedback))

    assert Tags.list_scope_members(ws.id, "status") ==
             ~w(status:backlog status:next status:in-flight status:review status:shipped status:cancelled)

    boards = ws.id |> Views.list_for_workspace() |> Enum.map(& &1.name) |> Enum.sort()
    assert boards == ["feedback", "ideas", "tickets"]
    assert length(Views.list_pinned(ws.id)) == 3

    orientation = Docs.get_orientation(ws.id)
    assert "How we work" in headings(orientation.blocks)
    assert "How we hand work to an agent" in headings(orientation.blocks)
    assert "The tags we start with" in headings(orientation.blocks)

    text = Jason.encode!(orientation.blocks)
    assert text =~ "Search before you file"
    assert text =~ "BG"
    assert Docs.get_current_by_slug(ws.id, "idea-template")
  end

  test "knowledge-base is the set every workspace used to get, plus a tickets board" do
    {ws, _owner} = create("knowledge-base")
    assert ws.template == "knowledge-base"
    assert length(Tags.list_slugs(ws.id)) == 20
    assert "brief" in Tags.list_slugs(ws.id) and "runbook" in Tags.list_slugs(ws.id)

    assert Tags.list_scope_members(ws.id, "status") ==
             ~w(status:backlog status:todo status:in-progress status:done status:cancelled)

    assert ws.id |> Views.list_for_workspace() |> Enum.map(& &1.name) == ["tickets"]
    assert Docs.get_current_by_slug(ws.id, "tip-template")
    assert Docs.get_current_by_slug(ws.id, "brief-template")
    refute Jason.encode!(Docs.get_orientation(ws.id).blocks) =~ "BG"
  end

  test "blank writes the frame and nothing else" do
    {ws, _owner} = create("blank")
    assert ws.template == "blank"
    assert Tags.list_slugs(ws.id) == []
    assert Views.list_for_workspace(ws.id) == []
    assert Docs.list_current(ws.id) |> Enum.reject(& &1.orientation) == []

    orientation = Docs.get_orientation(ws.id)
    assert orientation, "every workspace gets an orientation doc, whichever template"
    assert headings(orientation.blocks) == ["What this workspace is for", "Read these first", "How we work"]

    text = Jason.encode!(orientation.blocks)
    assert text =~ "(Fill in: how work moves here"
    refute text =~ "Search before you file"
  end

  test "every template is internally consistent" do
    for name <- Template.names() do
      defined = MapSet.new(Enum.map(Template.tags(name), &elem(&1, 0)))

      for {slug, _title, _summary, tags, _blocks} <- Template.docs(name) do
        assert MapSet.subset?(MapSet.new(tags), defined),
               "#{name}: doc #{slug} carries a tag the template does not create: #{inspect(tags)}"
      end

      scopes =
        Template.tags(name)
        |> Enum.map(fn {slug, _, _, _} -> Tags.scope_of(slug) end)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      for {view, _desc, config} <- Template.views(name), group = config["group_by"], group != nil do
        assert MapSet.member?(scopes, group),
               "#{name}: board #{view} groups by #{group}, which the template does not create"
      end

      for block <- Template.orientation_blocks(name) do
        assert {:ok, _} = Aveline.Blocks.Block.validate(block, mint_id?: true),
               "#{name}: orientation block did not validate: #{inspect(block)}"
      end

      for {slug, _title, _summary, _tags, blocks} <- Template.docs(name), block <- blocks do
        assert {:ok, _} = Aveline.Blocks.Block.validate(block, mint_id?: true),
               "#{name}: #{slug} block did not validate: #{inspect(block)}"
      end

      preview = Template.preview(name)
      assert preview["name"] == name
      assert length(preview["tags"]) == length(Template.tags(name))
    end
  end
end
