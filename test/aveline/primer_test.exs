defmodule Aveline.PrimerTest do
  @moduledoc """
  The primer is served to every agent in every workspace, so its blocks
  must be valid by the same rules as any doc, and the parts other code
  relies on must be there.
  """
  use ExUnit.Case, async: true

  alias Aveline.Blocks.Block
  alias Aveline.Primer

  test "changelog has an entry for every version up to the current one" do
    versions = Primer.changelog_since(0) |> Enum.map(&elem(&1, 0))
    assert versions == Enum.to_list(1..Primer.version())
    assert Primer.changelog_since(Primer.version()) == []
    for {_v, line} <- Primer.changelog_since(0), do: assert(is_binary(line) and line != "")
  end

  test "carries no tag list and no workflow of its own" do
    text = Jason.encode!(Primer.blocks())
    refute text =~ "ticket:bug"
    refute text =~ "in-flight"
    refute text =~ "Ticket subtype"
  end

  test "version is a positive integer and the payload carries it" do
    assert is_integer(Primer.version()) and Primer.version() >= 1
    assert %{"version" => v, "blocks" => blocks, "changelog" => log} = Primer.payload()
    assert v == Primer.version()
    assert blocks == Primer.blocks()
    assert is_list(log) and log != []
  end

  test "every block validates against Block.validate/2 with its own id" do
    for block <- Primer.blocks() do
      assert {:ok, _} = Block.validate(block),
             "primer block did not validate: #{inspect(block)}"
    end
  end

  test "ids are present, unique and stable across calls" do
    ids = Enum.map(Primer.blocks(), & &1["id"])
    assert Enum.all?(ids, &String.starts_with?(&1, "b_primer_"))
    assert length(ids) == length(Enum.uniq(ids))
    assert ids == Enum.map(Primer.blocks(), & &1["id"])
    assert "b_primer_person" in ids

    for %{"type" => "list", "items" => items} <- Primer.blocks(), item <- items do
      assert String.starts_with?(item["id"], "li_primer_")
    end
  end

  test "says the workspace doc wins, and carries the block for the person" do
    text =
      Primer.blocks()
      |> Enum.flat_map(fn
        %{"type" => "heading", "text" => t} -> [t]
        %{"type" => "paragraph", "content" => spans} -> Enum.map(spans, & &1["text"])
        _ -> []
      end)
      |> Enum.join(" ")

    assert text =~ "the workspace doc wins"
    assert Enum.any?(Primer.blocks(), &(&1["type"] == "heading" and &1["text"] == Primer.person_heading()))
  end
end
