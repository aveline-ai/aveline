defmodule Aveline.DocLinksTest do
  use Aveline.DataCase, async: false

  alias Aveline.Blocks.Block
  alias Aveline.Docs
  alias Aveline.Fixtures

  defp setup_ws do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    target = Fixtures.doc_fixture(ws, user, slug: "target-doc", title: "Target doc")
    %{user: user, ws: ws, target: target}
  end

  defp create_with_blocks(ws, user, blocks) do
    Docs.create_doc(%{
      workspace_id: ws.id,
      owner_id: user.id,
      actor_user_id: user.id,
      actor_type: "agent",
      title: "Story #{Fixtures.unique_int()}",
      blocks: blocks,
      intent: "test"
    })
  end

  describe "Block.validate doc_link" do
    test "valid doc_id + note normalizes" do
      uuid = Ecto.UUID.generate()

      assert {:ok, out} =
               Block.validate(
                 %{"type" => "doc_link", "doc_id" => uuid, "note" => [%{"text" => "why"}]},
                 mint_id?: true
               )

      assert out["doc_id"] == uuid
      assert out["note"] == [%{"text" => "why"}]
    end

    test "non-UUID doc_id is rejected" do
      assert {:error, msg} =
               Block.validate(%{"type" => "doc_link", "doc_id" => "some-slug"}, mint_id?: true)

      assert msg =~ "doc_id must be a UUID"
    end

    test "missing doc_id is rejected" do
      assert {:error, msg} = Block.validate(%{"type" => "doc_link"}, mint_id?: true)
      assert msg =~ "doc_link requires doc_id"
    end

    test "echoed target field is stripped on normalization" do
      uuid = Ecto.UUID.generate()

      assert {:ok, out} =
               Block.validate(
                 %{"type" => "doc_link", "doc_id" => uuid, "target" => %{"title" => "stale"}},
                 mint_id?: true
               )

      refute Map.has_key?(out, "target")
    end
  end

  describe "slug resolution + existence validation" do
    test "doc: slug resolves to the target's base_doc_id" do
      %{user: user, ws: ws, target: target} = setup_ws()

      assert {:ok, doc} =
               create_with_blocks(ws, user, [%{"type" => "doc_link", "doc" => "target-doc"}])

      assert [%{"type" => "doc_link", "doc_id" => doc_id} = blk] = doc.blocks
      assert doc_id == target.base_doc_id
      refute Map.has_key?(blk, "doc")

      # stored ops are the resolved ones — replay is deterministic
      assert [%{"op" => "append_block", "block" => %{"doc_id" => ^doc_id}}] = doc.operations
    end

    test "unknown slug is rejected with doc_link_target_not_found" do
      %{user: user, ws: ws} = setup_ws()

      assert {:error, :doc_link_target_not_found, msg} =
               create_with_blocks(ws, user, [%{"type" => "doc_link", "doc" => "nope"}])

      assert msg =~ "nope"
    end

    test "doc_id from another workspace is rejected" do
      %{target: target} = setup_ws()
      other_user = Fixtures.user_fixture()
      other_ws = Fixtures.workspace_fixture(other_user)

      assert {:error, :doc_link_target_not_found, _} =
               create_with_blocks(other_ws, other_user, [
                 %{"type" => "doc_link", "doc_id" => target.base_doc_id}
               ])
    end

    test "existing doc_id in the same workspace is accepted" do
      %{user: user, ws: ws, target: target} = setup_ws()

      assert {:ok, _doc} =
               create_with_blocks(ws, user, [
                 %{"type" => "doc_link", "doc_id" => target.base_doc_id}
               ])
    end

    test "modify_block patch with a new slug resolves too" do
      %{user: user, ws: ws, target: target} = setup_ws()
      second = Fixtures.doc_fixture(ws, user, slug: "second-doc", title: "Second doc")

      {:ok, doc} =
        create_with_blocks(ws, user, [%{"type" => "doc_link", "doc_id" => target.base_doc_id}])

      [%{"id" => block_id}] = doc.blocks

      ops = [%{"op" => "modify_block", "id" => block_id, "patch" => %{"doc" => "second-doc"}}]

      assert {:ok, v2} =
               Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])

      assert [%{"doc_id" => doc_id}] = v2.blocks
      assert doc_id == second.base_doc_id
    end
  end

  describe "enrich_doc_links/2" do
    test "live target echoes slug/title/summary and deleted: false" do
      %{user: user, ws: ws, target: target} = setup_ws()

      {:ok, doc} =
        create_with_blocks(ws, user, [
          %{"type" => "doc_link", "doc_id" => target.base_doc_id, "note" => [%{"text" => "start"}]}
        ])

      assert [%{"target" => t}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert t["slug"] == "target-doc"
      assert t["title"] == "Target doc"
      assert t["deleted"] == false
    end

    test "soft-deleted target echoes latest metadata with deleted: true" do
      %{user: user, ws: ws, target: target} = setup_ws()

      {:ok, doc} =
        create_with_blocks(ws, user, [%{"type" => "doc_link", "doc_id" => target.base_doc_id}])

      {:ok, _} = Docs.soft_delete(target, user.id)

      assert [%{"target" => t}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert t["deleted"] == true
      assert t["title"] == "Target doc"
    end

    test "target echoes tags, scrubbed of soft-deleted ones" do
      user = Fixtures.user_fixture()
      ws = Fixtures.workspace_fixture(user)
      {:ok, _} = Aveline.Tags.create(ws.id, "keepme", "Stays live.", user.id)
      {:ok, doomed} = Aveline.Tags.create(ws.id, "doomed", "Gets deleted.", user.id)
      target = Fixtures.doc_fixture(ws, user, slug: "tagged-target", tags: ["keepme", "doomed"])

      {:ok, doc} =
        create_with_blocks(ws, user, [%{"type" => "doc_link", "doc_id" => target.base_doc_id}])

      assert [%{"target" => t}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert Enum.sort(t["tags"]) == ["doomed", "keepme"]

      {:ok, _} = Aveline.Tags.delete(doomed, user.id)

      assert [%{"target" => t2}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert t2["tags"] == ["keepme"]
    end

    test "non-doc_link blocks pass through untouched" do
      %{ws: ws} = setup_ws()
      blocks = [%{"id" => "b_x", "type" => "paragraph", "content" => [%{"text" => "hi"}]}]
      assert Docs.enrich_blocks(blocks, ws.id) == blocks
    end
  end

  describe "inline span links" do
    test "span link doc_id normalizes and strips a pasted target echo" do
      uuid = Ecto.UUID.generate()

      assert {:ok, out} =
               Block.validate(
                 %{
                   "type" => "paragraph",
                   "content" => [
                     %{
                       "text" => "see this",
                       "link" => %{"doc_id" => String.upcase(uuid), "target" => %{"title" => "stale"}}
                     }
                   ]
                 },
                 mint_id?: true
               )

      assert [%{"link" => link}] = out["content"]
      assert link == %{"doc_id" => uuid}
    end

    test "span link with both href and doc_id is rejected" do
      assert {:error, msg} =
               Block.validate(
                 %{
                   "type" => "paragraph",
                   "content" => [
                     %{"text" => "x", "link" => %{"href" => "https://x.com", "doc_id" => Ecto.UUID.generate()}}
                   ]
                 },
                 mint_id?: true
               )

      assert msg =~ "not both"
    end

    test "span link with non-UUID doc_id is rejected" do
      assert {:error, msg} =
               Block.validate(
                 %{"type" => "paragraph", "content" => [%{"text" => "x", "link" => %{"doc_id" => "some-slug"}}]},
                 mint_id?: true
               )

      assert msg =~ "must be a UUID"
    end

    test "link: {doc: slug} in a paragraph resolves to the target's base_doc_id" do
      %{user: user, ws: ws, target: target} = setup_ws()

      assert {:ok, doc} =
               create_with_blocks(ws, user, [
                 %{
                   "type" => "paragraph",
                   "content" => [
                     %{"text" => "see "},
                     %{"text" => "the target", "link" => %{"doc" => "target-doc"}}
                   ]
                 }
               ])

      assert [%{"content" => [_, %{"link" => link}]}] = doc.blocks
      assert link == %{"doc_id" => target.base_doc_id}

      # stored ops carry the resolved form too
      assert [%{"block" => %{"content" => [_, %{"link" => stored_link}]}}] = doc.operations
      assert stored_link == %{"doc_id" => target.base_doc_id}
    end

    test "unknown slug in a span is rejected with doc_link_target_not_found" do
      %{user: user, ws: ws} = setup_ws()

      assert {:error, :doc_link_target_not_found, msg} =
               create_with_blocks(ws, user, [
                 %{"type" => "paragraph", "content" => [%{"text" => "x", "link" => %{"doc" => "ghost"}}]}
               ])

      assert msg =~ "ghost"
    end

    test "span doc_id from another workspace is rejected" do
      %{target: target} = setup_ws()
      other_user = Fixtures.user_fixture()
      other_ws = Fixtures.workspace_fixture(other_user)

      assert {:error, :doc_link_target_not_found, _} =
               create_with_blocks(other_ws, other_user, [
                 %{
                   "type" => "paragraph",
                   "content" => [%{"text" => "x", "link" => %{"doc_id" => target.base_doc_id}}]
                 }
               ])
    end

    test "spans in list items, table cells, and doc_link notes resolve too" do
      %{user: user, ws: ws, target: target} = setup_ws()
      mention = %{"text" => "see target", "link" => %{"doc" => "target-doc"}}

      assert {:ok, doc} =
               create_with_blocks(ws, user, [
                 %{"type" => "list", "ordered" => false, "items" => [%{"content" => [mention]}]},
                 %{"type" => "table", "headers" => ["col"], "rows" => [[[mention]]]},
                 %{"type" => "doc_link", "doc" => "target-doc", "note" => [mention]}
               ])

      [list, table, dl] = doc.blocks
      assert [%{"content" => [%{"link" => %{"doc_id" => id}}]}] = list["items"]
      assert id == target.base_doc_id
      assert [[[%{"link" => %{"doc_id" => ^id}}]]] = table["rows"]
      assert [%{"link" => %{"doc_id" => ^id}}] = dl["note"]
    end

    test "modify_block patch with span content resolves slugs" do
      %{user: user, ws: ws, target: target} = setup_ws()

      {:ok, doc} =
        create_with_blocks(ws, user, [
          %{"type" => "paragraph", "content" => [%{"text" => "plain"}]}
        ])

      [%{"id" => block_id}] = doc.blocks

      ops = [
        %{
          "op" => "modify_block",
          "id" => block_id,
          "patch" => %{"content" => [%{"text" => "now linked", "link" => %{"doc" => "target-doc"}}]}
        }
      ]

      assert {:ok, v2} =
               Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])

      assert [%{"content" => [%{"link" => %{"doc_id" => id}}]}] = v2.blocks
      assert id == target.base_doc_id
    end

    test "enrichment echoes the target under link.target, deleted included" do
      %{user: user, ws: ws, target: target} = setup_ws()

      {:ok, doc} =
        create_with_blocks(ws, user, [
          %{
            "type" => "paragraph",
            "content" => [%{"text" => "see target", "link" => %{"doc" => "target-doc"}}]
          }
        ])

      assert [%{"content" => [%{"link" => %{"target" => t}}]}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert t["slug"] == "target-doc"
      assert t["title"] == "Target doc"
      assert t["deleted"] == false

      {:ok, _} = Docs.soft_delete(target, user.id)

      assert [%{"content" => [%{"link" => %{"target" => t2}}]}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert t2["deleted"] == true
      assert t2["title"] == "Target doc"
    end

    test "external href links pass through resolution and gain no echo" do
      %{user: user, ws: ws} = setup_ws()

      {:ok, doc} =
        create_with_blocks(ws, user, [
          %{
            "type" => "paragraph",
            "content" => [%{"text" => "docs", "link" => %{"href" => "https://example.com"}}]
          }
        ])

      assert [%{"content" => [%{"link" => link}]}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert link == %{"href" => "https://example.com"}
    end
  end

  describe "search text" do
    test "doc_link note is searchable" do
      %{user: user, ws: ws, target: target} = setup_ws()

      {:ok, doc} =
        create_with_blocks(ws, user, [
          %{
            "type" => "doc_link",
            "doc_id" => target.base_doc_id,
            "note" => [%{"text" => "zanzibar onboarding stop"}]
          }
        ])

      assert doc.search_text =~ "zanzibar"
    end
  end
end
