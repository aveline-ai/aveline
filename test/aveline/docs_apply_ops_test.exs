defmodule Aveline.DocsApplyOpsTest do
  use Aveline.DataCase, async: false

  alias Aveline.Comments
  alias Aveline.Docs
  alias Aveline.Fixtures
  alias Aveline.Repo

  defp setup_doc_with_comment_on_block(block_id) do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)

    blocks = [
      %{"id" => block_id, "type" => "paragraph", "content" => [%{"text" => "first"}]},
      %{"id" => "b_other", "type" => "paragraph", "content" => [%{"text" => "other"}]}
    ]

    doc = Fixtures.doc_fixture(ws, user, blocks: blocks)

    {:ok, comment} =
      Comments.create_comment(%{
        "doc_id" => doc.id,
        "block_id" => block_id,
        "body" => "this needs clarification",
        "actor_user_id" => user.id,
        "actor_type" => "human"
      })

    %{user: user, ws: ws, doc: doc, comment: comment}
  end

  describe "agent apply_ops with touched-block coverage" do
    test "missing disposition on a comment anchored to a modified block is rejected" do
      %{user: user, doc: doc, comment: c} = setup_doc_with_comment_on_block("b_one")

      ops = [%{"op" => "modify_block", "id" => "b_one", "patch" => %{"content" => [%{"text" => "edited"}]}}]

      assert {:error, {:disposition_missing, missing}} =
               Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"},
                 dispositions: []
               )

      assert c.id in missing
    end

    test "comment on an untouched block is NOT required" do
      %{user: user, doc: doc} = setup_doc_with_comment_on_block("b_one")

      ops = [%{"op" => "modify_block", "id" => "b_other", "patch" => %{"content" => [%{"text" => "edited"}]}}]

      assert {:ok, _new_doc} =
               Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"},
                 dispositions: []
               )
    end

    test "resolve disposition posts an agent reply and marks the parent resolved" do
      %{user: user, doc: doc, comment: c} = setup_doc_with_comment_on_block("b_one")

      ops = [%{"op" => "modify_block", "id" => "b_one", "patch" => %{"content" => [%{"text" => "edited"}]}}]

      assert {:ok, new_doc} =
               Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"},
                 dispositions: [
                   %{
                     "comment_id" => c.id,
                     "action" => "resolve",
                     "reply" => "Reworded — should be clearer now."
                   }
                 ]
               )

      reloaded = Repo.get!(Aveline.Comments.Comment, c.id)
      assert reloaded.resolved_at != nil
      assert reloaded.resolved_by_doc_id == new_doc.id

      # The reply lives in the thread as a child comment on the new version,
      # inheriting the parent's block anchor.
      reply =
        Aveline.Comments.list_for_base_doc(doc.base_doc_id)
        |> Enum.find(&(&1.parent_comment_id == c.id))

      assert reply
      assert reply.body == "Reworded — should be clearer now."
      assert reply.doc_id == new_doc.id
      assert reply.block_id == "b_one"
      assert reply.actor_type == "agent"
    end

    test "leave on a deleted block is rejected" do
      %{user: user, doc: doc, comment: c} = setup_doc_with_comment_on_block("b_one")

      ops = [%{"op" => "delete_block", "id" => "b_one"}]

      assert {:error, {:leave_on_deleted_block, bad_id}} =
               Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"},
                 dispositions: [%{"comment_id" => c.id, "action" => "leave"}]
               )

      assert bad_id == c.id
    end
  end
end
