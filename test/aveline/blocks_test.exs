defmodule Aveline.BlocksTest do
  use ExUnit.Case, async: true

  alias Aveline.Blocks.Block
  alias Aveline.Blocks.Document
  alias Aveline.Blocks.Id
  alias Aveline.Blocks.Inline
  alias Aveline.Blocks.Operation

  describe "Block.validate" do
    test "heading: requires level 1-3 + text" do
      assert {:ok, %{"id" => "b_" <> _, "type" => "heading", "level" => 2, "text" => "X"}} =
               Block.validate(%{"type" => "heading", "level" => 2, "text" => "X"}, mint_id?: true)

      assert {:error, _} = Block.validate(%{"type" => "heading", "level" => 5, "text" => "X"})
      assert {:error, _} = Block.validate(%{"type" => "heading"})
    end

    test "paragraph: validates inline spans + marks" do
      result =
        Block.validate(
          %{
            "type" => "paragraph",
            "content" => [
              %{"text" => "hello "},
              %{"text" => "world", "marks" => ["bold"]}
            ]
          },
          mint_id?: true
        )

      assert {:ok, %{"type" => "paragraph", "content" => content}} = result
      assert [%{"text" => "hello "}, %{"text" => "world", "marks" => ["bold"]}] = content
    end

    test "paragraph: rejects unknown marks" do
      assert {:error, msg} =
               Block.validate(%{
                 "type" => "paragraph",
                 "id" => "b_aaaaaaaaaaaaaaaaaaaaaa",
                 "content" => [%{"text" => "x", "marks" => ["rainbow"]}]
               })

      assert msg =~ "marks"
    end

    test "code: language defaults to null" do
      assert {:ok, %{"type" => "code", "language" => nil, "content" => "x"}} =
               Block.validate(%{"type" => "code", "content" => "x"}, mint_id?: true)
    end

    test "list: mints list-item ids, validates content" do
      assert {:ok, %{"items" => [%{"id" => "li_" <> _, "content" => [%{"text" => "x"}]}]}} =
               Block.validate(
                 %{
                   "type" => "list",
                   "items" => [%{"content" => [%{"text" => "x"}]}]
                 },
                 mint_id?: true
               )
    end

    test "table: requires headers and rows of matching length" do
      assert {:error, msg} =
               Block.validate(
                 %{
                   "type" => "table",
                   "headers" => ["a", "b"],
                   "rows" => [[[%{"text" => "x"}]]]
                 },
                 mint_id?: true
               )

      assert msg =~ "same length"
    end

    test "metadata: free-form, preserved" do
      assert {:ok, %{"metadata" => %{"content_intent" => "explain"}}} =
               Block.validate(
                 %{
                   "type" => "heading",
                   "level" => 1,
                   "text" => "x",
                   "metadata" => %{"content_intent" => "explain"}
                 },
                 mint_id?: true
               )
    end
  end

  describe "Inline.validate_spans" do
    test "rejects non-string text" do
      assert {:error, _} = Inline.validate_spans([%{"text" => 42}])
    end

    test "to_text concatenates spans" do
      assert Inline.to_text([%{"text" => "a"}, %{"text" => "b"}]) == "ab"
    end
  end

  describe "Id" do
    test "mints + validates prefix" do
      id = Id.mint_block()
      assert String.starts_with?(id, "b_")
      assert Id.valid_block_id?(id)
      refute Id.valid_block_id?("li_" <> binary_part(id, 2, byte_size(id) - 2))
    end
  end

  describe "Operation.validate" do
    test "rejects unknown op" do
      assert {:error, msg} = Operation.validate(%{"op" => "nuke"})
      assert msg =~ "unknown op"
    end

    test "append_block: validates embedded block" do
      assert {:ok, %{"op" => "append_block", "block" => %{"id" => "b_" <> _}}} =
               Operation.validate(%{
                 "op" => "append_block",
                 "block" => %{"type" => "heading", "level" => 1, "text" => "x"}
               })
    end

    test "metadata on op is preserved" do
      assert {:ok, %{"metadata" => %{"diff_intent" => "fix typo"}}} =
               Operation.validate(%{
                 "op" => "delete_block",
                 "id" => "b_aaaaaaaaaaaaaaaaaaaaaa",
                 "metadata" => %{"diff_intent" => "fix typo"}
               })
    end
  end

  describe "Document.apply_ops" do
    setup do
      {:ok, h} =
        Block.validate(%{"type" => "heading", "level" => 1, "text" => "hi"}, mint_id?: true)

      {:ok, p} =
        Block.validate(
          %{"type" => "paragraph", "content" => [%{"text" => "x"}]},
          mint_id?: true
        )

      {:ok, blocks: [h, p], h: h, p: p}
    end

    test "append_block adds at end", %{blocks: blocks} do
      assert {:ok, [_, _, %{"type" => "code"}]} =
               Document.apply_ops(blocks, [
                 %{
                   "op" => "append_block",
                   "block" => %{"type" => "code", "content" => "x"}
                 }
               ])
    end

    test "insert_block inserts after the named block", %{blocks: blocks, h: h} do
      assert {:ok, [h_seen, code, _p]} =
               Document.apply_ops(blocks, [
                 %{
                   "op" => "insert_block",
                   "after" => h["id"],
                   "block" => %{"type" => "code", "content" => "x"}
                 }
               ])

      assert h_seen["id"] == h["id"]
      assert code["type"] == "code"
    end

    test "modify_block patches in place", %{blocks: blocks, h: h} do
      assert {:ok, [updated_h | _]} =
               Document.apply_ops(blocks, [
                 %{
                   "op" => "modify_block",
                   "id" => h["id"],
                   "patch" => %{"text" => "renamed"}
                 }
               ])

      assert updated_h["id"] == h["id"]
      assert updated_h["text"] == "renamed"
    end

    test "modify_block rejects type changes", %{blocks: blocks, h: h} do
      assert {:error, msg, 0} =
               Document.apply_ops(blocks, [
                 %{
                   "op" => "modify_block",
                   "id" => h["id"],
                   "patch" => %{"type" => "paragraph"}
                 }
               ])

      assert msg =~ "cannot change block type"
    end

    test "delete_block removes by id", %{blocks: blocks, p: p} do
      assert {:ok, [_]} =
               Document.apply_ops(blocks, [
                 %{"op" => "delete_block", "id" => p["id"]}
               ])
    end

    test "move_block reorders; nil after = move to front", %{blocks: blocks, p: p, h: h} do
      assert {:ok, [first, second]} =
               Document.apply_ops(blocks, [
                 %{"op" => "move_block", "id" => p["id"], "after" => nil}
               ])

      assert first["id"] == p["id"]
      assert second["id"] == h["id"]
    end

    test "batched ops apply in order", %{blocks: blocks, h: h} do
      ops = [
        %{
          "op" => "insert_block",
          "after" => h["id"],
          "block" => %{"type" => "code", "content" => "x"}
        },
        %{
          "op" => "modify_block",
          "id" => h["id"],
          "patch" => %{"text" => "edited"}
        }
      ]

      assert {:ok, [first, second, _]} = Document.apply_ops(blocks, ops)
      assert first["text"] == "edited"
      assert second["type"] == "code"
    end

    test "missing reference rejects with index", %{blocks: blocks} do
      assert {:error, msg, 0} =
               Document.apply_ops(blocks, [
                 %{
                   "op" => "modify_block",
                   "id" => "b_doesnotexist0000000000",
                   "patch" => %{"text" => "x"}
                 }
               ])

      assert msg =~ "not found"
    end
  end
end
