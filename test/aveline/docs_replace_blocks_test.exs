defmodule Aveline.DocsReplaceBlocksTest do
  @moduledoc """
  The `--blocks` full-replace edit path: caller sends the whole desired
  document, server reconciles by stable block id and ships a new version.
  Reconciliation must compose with the open-comment disposition gate
  exactly like the surgical ops path.
  """
  use Aveline.DataCase, async: false

  alias Aveline.Comments
  alias Aveline.Docs
  alias Aveline.Fixtures

  defp para(id, text),
    do: %{"id" => id, "type" => "paragraph", "content" => [%{"text" => text}]}

  defp setup_doc(blocks) do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    doc = Fixtures.doc_fixture(ws, user, blocks: blocks)
    %{user: user, ws: ws, doc: doc}
  end

  defp attrs(user), do: %{actor_user_id: user.id, actor_type: "agent"}

  describe "replace_blocks reconciliation" do
    test "changes one block, keeps the rest, ships a new version" do
      %{user: user, doc: doc} = setup_doc([para("b_one", "first"), para("b_two", "second")])

      desired = [para("b_one", "first EDITED"), para("b_two", "second")]

      assert {:ok, v2} = Docs.replace_blocks(doc, desired, attrs(user), intent: "edit")
      assert v2.version_number == doc.version_number + 1
      assert [%{"id" => "b_one"} = one, %{"id" => "b_two"} = two] = v2.blocks
      assert one["content"] == [%{"text" => "first EDITED"}]
      assert two["content"] == [%{"text" => "second"}]
    end

    test "an id-less block is minted and appended; omitted blocks are deleted" do
      %{user: user, doc: doc} = setup_doc([para("b_one", "keep"), para("b_two", "drop")])

      # Keep b_one, drop b_two, add a brand-new block (no id).
      desired = [para("b_one", "keep"), %{"type" => "paragraph", "content" => [%{"text" => "new"}]}]

      assert {:ok, v2} = Docs.replace_blocks(doc, desired, attrs(user), intent: "restructure")
      assert [%{"id" => "b_one"}, %{"id" => minted} = added] = v2.blocks
      assert String.starts_with?(minted, "b_")
      assert added["content"] == [%{"text" => "new"}]
      refute Enum.any?(v2.blocks, &(&1["id"] == "b_two"))
    end

    test "reordering existing blocks needs no disposition and is reflected verbatim" do
      %{user: user, doc: doc} = setup_doc([para("b_one", "one"), para("b_two", "two")])

      desired = [para("b_two", "two"), para("b_one", "one")]

      assert {:ok, v2} = Docs.replace_blocks(doc, desired, attrs(user), intent: "reorder")
      assert Enum.map(v2.blocks, & &1["id"]) == ["b_two", "b_one"]
    end

    test "duplicate block ids are rejected" do
      %{user: user, doc: doc} = setup_doc([para("b_one", "x")])

      desired = [para("b_one", "x"), para("b_one", "y")]

      assert {:error, msg} = Docs.replace_blocks(doc, desired, attrs(user), intent: "oops")
      assert msg =~ "duplicate block id"
    end
  end

  describe "replace_blocks + open-comment gate" do
    defp setup_doc_with_comment(block_id) do
      %{user: user, doc: doc} = ctx = setup_doc([para(block_id, "first"), para("b_other", "other")])

      {:ok, comment} =
        Comments.create_comment(%{
          "doc_id" => doc.id,
          "block_id" => block_id,
          "body" => "needs clarification",
          "actor_user_id" => user.id,
          "actor_type" => "human"
        })

      Map.put(ctx, :comment, comment)
    end

    test "changing a commented block without a disposition is rejected" do
      %{user: user, doc: doc, comment: c} = setup_doc_with_comment("b_one")

      desired = [para("b_one", "REWORDED"), para("b_other", "other")]

      assert {:error, {:disposition_missing, missing}} =
               Docs.replace_blocks(doc, desired, attrs(user), dispositions: [])

      assert c.id in missing
    end

    test "a HUMAN actor may change a commented block with no disposition (migration path)" do
      # The chart migration rewrites every chart block (inline -> query_ref)
      # as actor_type: "human" precisely so it need not disposition every
      # open comment on a chart. Lock that bypass in.
      %{user: user, doc: doc} = setup_doc_with_comment("b_one")

      desired = [para("b_one", "REWORDED"), para("b_other", "other")]

      assert {:ok, v2} =
               Docs.replace_blocks(
                 doc,
                 desired,
                 %{actor_user_id: user.id, actor_type: "human"},
                 dispositions: []
               )

      assert v2.version_number == doc.version_number + 1
    end

    test "changing an untouched block leaves the comment thread alone" do
      %{user: user, doc: doc} = setup_doc_with_comment("b_one")

      # Only b_other changes; b_one (commented) is byte-identical -> no gate.
      desired = [para("b_one", "first"), para("b_other", "other EDITED")]

      assert {:ok, _v2} = Docs.replace_blocks(doc, desired, attrs(user), dispositions: [])
    end

    test "a disposition on the touched thread ships the edit" do
      %{user: user, doc: doc, comment: c} = setup_doc_with_comment("b_one")

      desired = [para("b_one", "REWORDED"), para("b_other", "other")]

      assert {:ok, v2} =
               Docs.replace_blocks(doc, desired, attrs(user),
                 dispositions: [%{"comment_id" => c.id, "action" => "resolve", "reply" => "fixed"}]
               )

      live = Comments.get_current_by_base(c.base_comment_id)
      assert live.resolved_at != nil
      assert live.doc_id == v2.id
    end

    test "deleting a commented block cannot be left open" do
      %{user: user, doc: doc, comment: c} = setup_doc_with_comment("b_one")

      # Drop the commented block entirely.
      desired = [para("b_other", "other")]

      assert {:error, {:leave_on_deleted_block, bad}} =
               Docs.replace_blocks(doc, desired, attrs(user),
                 dispositions: [%{"comment_id" => c.id, "action" => "leave"}]
               )

      assert bad == c.id
    end
  end
end
