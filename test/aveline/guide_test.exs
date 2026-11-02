defmodule Aveline.GuideTest do
  @moduledoc """
  The guide is served to every agent in every workspace, so its blocks
  must be valid by the same rules as any doc, it must stay short where it
  rides on every orientation, and it must carry no opinion about how a
  team works.
  """
  use ExUnit.Case, async: true

  alias Aveline.Blocks.Block
  alias Aveline.Guide

  # Words that belong to a template, never to the guide: team vocabulary
  # and workflow rules. Matched on word boundaries.
  @opinion [~r/\bBG\b/, ~r/\bFG\b/, ~r/ticket:bug/, ~r/in-flight/, ~r/status:todo/, ~r/Search before you file/i, ~r/\bfile it\b/i]

  test "changelog has an entry for every version up to the current one" do
    versions = Guide.changelog_since(0) |> Enum.map(&elem(&1, 0))
    assert versions == Enum.to_list(1..Guide.version())
    assert Guide.changelog_since(Guide.version()) == []
    for {_v, line} <- Guide.changelog_since(0), do: assert(is_binary(line) and line != "")
  end

  test "carries no tag list, no workflow and no team vocabulary" do
    text = plain_text(Guide.blocks()) <> " " <> plain_text(Guide.summary_blocks())

    for pattern <- @opinion do
      refute text =~ pattern, "the guide matches #{inspect(pattern)}, which belongs to a template"
    end
  end

  test "the summary stays short, because it rides on every orientation" do
    words = Guide.summary_blocks() |> plain_text() |> String.split(~r/\s+/, trim: true) |> length()
    assert words <= 240, "summary is #{words} words; keep it under 240 or move text to the full guide"
    assert length(Guide.summary_blocks()) <= 3
  end

  test "payloads carry the version and the right cut" do
    assert %{"version" => v, "blocks" => blocks, "changelog" => log} = Guide.payload()
    assert v == Guide.version()
    assert blocks == Guide.blocks()
    assert is_list(log) and log != []

    assert %{"version" => ^v, "blocks" => summary} = Guide.summary_payload()
    assert summary == Guide.summary_blocks()
    refute Map.has_key?(Guide.summary_payload(), "changelog")
  end

  test "every block of both cuts validates against Block.validate/2 with its own id" do
    for block <- Guide.blocks() ++ Guide.summary_blocks() do
      assert {:ok, _} = Block.validate(block), "guide block did not validate: #{inspect(block)}"
    end
  end

  test "ids are present, unique and stable across calls" do
    for {blocks, prefix} <- [{Guide.blocks(), "b_guide_"}, {Guide.summary_blocks(), "b_guide_summary_"}] do
      ids = Enum.map(blocks, & &1["id"])
      assert Enum.all?(ids, &String.starts_with?(&1, prefix))
      assert length(ids) == length(Enum.uniq(ids))

      for %{"type" => "list", "items" => items} <- blocks, item <- items do
        assert String.starts_with?(item["id"], "li_guide")
      end
    end

    assert Enum.map(Guide.blocks(), & &1["id"]) == Enum.map(Guide.blocks(), & &1["id"])
    assert "b_guide_person" in Enum.map(Guide.blocks(), & &1["id"])
  end

  test "says the workspace doc wins, names the templates, and carries the block for the person" do
    text = plain_text(Guide.blocks())
    assert text =~ "the workspace doc wins"
    for name <- Aveline.Workspaces.Template.names(), do: assert(text =~ name)
    assert Enum.any?(Guide.blocks(), &(&1["type"] == "heading" and &1["text"] == Guide.person_heading()))
  end

  defp plain_text(blocks) do
    blocks
    |> Enum.flat_map(fn
      %{"type" => "heading", "text" => t} -> [t]
      %{"type" => "paragraph", "content" => spans} -> Enum.map(spans, & &1["text"])
      %{"type" => "list", "items" => items} -> Enum.flat_map(items, fn it -> Enum.map(it["content"], & &1["text"]) end)
      _ -> []
    end)
    |> Enum.join(" ")
  end
end
