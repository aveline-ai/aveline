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

      # The live row for the parent thread is now the auto-forwarded
      # copy pinned to the new doc-version — resolve lands there. The
      # original v1 row (c.id) keeps resolved_at = NULL so time-travel
      # to doc v1 shows the thread as open at that time.
      live = Aveline.Comments.get_current_by_base(c.base_comment_id)
      assert live.resolved_at != nil
      assert live.resolved_by_doc_id == new_doc.id
      assert live.doc_id == new_doc.id

      # The reply lives in the thread as a child comment on the new version,
      # inheriting the parent's block anchor.
      reply =
        Aveline.Comments.list_for_base_doc(doc.base_doc_id)
        |> Enum.find(&(&1.parent_comment_id == c.base_comment_id))

      assert reply
      assert reply.body == "Reworded — should be clearer now."
      assert reply.doc_id == new_doc.id
      assert reply.block_id == "b_one"
      assert reply.actor_type == "agent"
    end

    test "auto-forward: every live comment gets a new row pinned to the new doc-version" do
      %{user: user, doc: doc, comment: c} = setup_doc_with_comment_on_block("b_one")

      # untouched ops — disposition not required for c.
      ops = [
        %{"op" => "modify_block", "id" => "b_other",
          "patch" => %{"content" => [%{"text" => "edited"}]}}
      ]

      assert {:ok, new_doc} =
               Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"},
                 dispositions: []
               )

      # The original v1 row is now superseded; new v2 row exists, pinned
      # to the new doc-version, with body / block_id / resolved_at all
      # carried forward verbatim.
      v1 = Repo.get!(Aveline.Comments.Comment, c.id)
      assert v1.superseded
      assert v1.deleted_at == nil

      live = Aveline.Comments.get_current_by_base(c.base_comment_id)
      assert live.version_number == 2
      assert live.doc_id == new_doc.id
      assert live.block_id == "b_one"
      assert live.body == c.body
      assert live.resolved_at == nil
    end

    test "list_for_doc_version returns each version's pinned snapshot" do
      %{user: user, doc: doc, comment: c} = setup_doc_with_comment_on_block("b_one")

      # Ship v2 untouched — auto-forward kicks in.
      {:ok, v2_doc} =
        Docs.apply_ops(doc, [
          %{"op" => "modify_block", "id" => "b_other",
            "patch" => %{"content" => [%{"text" => "edited"}]}}
        ], %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])

      v1_snapshot = Aveline.Comments.list_for_doc_version(doc.id)
      v2_snapshot = Aveline.Comments.list_for_doc_version(v2_doc.id)

      # v1 sees the original comment row; v2 sees the auto-forwarded one.
      assert length(v1_snapshot) == 1
      assert hd(v1_snapshot).id == c.id

      assert length(v2_snapshot) == 1
      assert hd(v2_snapshot).id != c.id
      assert hd(v2_snapshot).base_comment_id == c.base_comment_id
      assert hd(v2_snapshot).doc_id == v2_doc.id
    end

    test "time-travel preserves the open-then-resolved-now story" do
      %{user: user, doc: doc, comment: c} = setup_doc_with_comment_on_block("b_one")

      # Agent ships v2 with a resolve disposition on c.
      ops = [%{"op" => "modify_block", "id" => "b_one",
               "patch" => %{"content" => [%{"text" => "edited"}]}}]

      {:ok, v2_doc} =
        Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"},
          dispositions: [
            %{"comment_id" => c.base_comment_id,
              "action" => "resolve",
              "reply" => "Addressed."}
          ]
        )

      # v1 snapshot: thread open (resolved_at NULL on the v1 row).
      v1_snapshot = Aveline.Comments.list_for_doc_version(doc.id)
      v1_parent = Enum.find(v1_snapshot, &is_nil(&1.parent_comment_id))
      assert v1_parent.resolved_at == nil

      # v2 snapshot: thread resolved on the auto-forwarded row.
      v2_snapshot = Aveline.Comments.list_for_doc_version(v2_doc.id)
      v2_parent = Enum.find(v2_snapshot, &is_nil(&1.parent_comment_id))
      assert v2_parent.resolved_at != nil
      assert v2_parent.resolved_by_doc_id == v2_doc.id

      # Agent reply lives only on v2 (it didn't exist on v1).
      assert Enum.any?(v2_snapshot, &(&1.parent_comment_id == c.base_comment_id))
      refute Enum.any?(v1_snapshot, &(&1.parent_comment_id == c.base_comment_id))
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
