defmodule Aveline.TagVersioningTest do
  use Aveline.DataCase, async: false

  alias Aveline.Docs
  alias Aveline.Fixtures
  alias Aveline.Tags

  setup do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    {:ok, tag} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)
    %{user: user, ws: ws, tag: tag}
  end

  describe "versioned edits" do
    test "recolor inserts a new version; the old row is superseded, not deleted", %{
      user: user,
      ws: ws,
      tag: tag
    } do
      {:ok, v2} = Tags.edit(tag, %{color: "#22c55e"}, user.id)

      assert v2.base_tag_id == tag.base_tag_id
      assert v2.version_number == 2
      assert v2.color == "#22c55e"
      assert v2.slug == "deploys"

      old = Repo.get!(Tags.Tag, tag.id)
      assert old.superseded
      assert old.deleted_at == nil

      # Only the new version is visible.
      assert Tags.get(ws.id, "deploys").id == v2.id
    end

    test "rename versions the tag AND cascades the slug across docs", %{
      user: user,
      ws: ws,
      tag: tag
    } do
      doc = Fixtures.doc_fixture(ws, user, title: "Uses it", tags: ["deploys"])

      {:ok, v2} = Tags.edit(tag, %{slug: "shipping"}, user.id)
      assert v2.version_number == 2
      assert v2.slug == "shipping"

      assert Docs.get_current_by_slug(ws.id, doc.slug).tags == ["shipping"]
      assert Tags.get(ws.id, "deploys") == nil
    end

    test "no-op edit doesn't version", %{user: user, tag: tag} do
      assert {:ok, same} = Tags.edit(tag, %{description: tag.description}, user.id)
      assert same.id == tag.id
      assert same.version_number == 1
    end

    test "bad color rejected; clearing color works", %{user: user, tag: tag} do
      assert {:error, %Ecto.Changeset{}} = Tags.edit(tag, %{color: "green"}, user.id)

      {:ok, v2} = Tags.edit(tag, %{color: "#123ABC"}, user.id)
      assert v2.color == "#123abc"

      {:ok, v3} = Tags.edit(v2, %{color: nil}, user.id)
      assert v3.color == nil
      assert v3.version_number == 3
    end

    test "rename into an occupied slug is rejected", %{user: user, ws: ws, tag: tag} do
      {:ok, _} = Tags.create(ws.id, "shipping", "Other tag.", user.id)
      assert {:error, :destination_exists} = Tags.edit(tag, %{slug: "shipping"}, user.id)
    end
  end

  describe "soft delete + restore" do
    test "deleted tag vanishes from reads but docs keep it; restore brings it back", %{
      user: user,
      ws: ws,
      tag: tag
    } do
      doc = Fixtures.doc_fixture(ws, user, title: "Tagged", tags: ["deploys"])

      {:ok, _} = Tags.delete(Tags.get(ws.id, "deploys"), user.id)

      # Invisible everywhere...
      assert Tags.get(ws.id, "deploys") == nil
      refute "deploys" in Docs.list_workspace_tags(ws.id)
      assert Docs.get_current_by_slug(ws.id, doc.slug).tags == []

      # ...but the doc row still carries the slug, so restore is total.
      {:ok, _} = Tags.restore(Tags.get_deleted(ws.id, "deploys"), user.id)
      assert Docs.get_current_by_slug(ws.id, doc.slug).tags == ["deploys"]

      _ = tag
    end

    test "a superseded row is never the restore target", %{user: user, ws: ws, tag: tag} do
      {:ok, v2} = Tags.edit(tag, %{color: "#123abc"}, user.id)
      {:ok, _} = Tags.delete(v2, user.id)

      target = Tags.get_deleted(ws.id, "deploys")
      assert target.id == v2.id
      assert {:ok, _} = Tags.restore(target, user.id)

      # Belt and suspenders: restoring a superseded row is refused.
      old = Repo.get!(Tags.Tag, tag.id)
      assert {:error, msg} = Tags.restore(old, user.id)
      assert msg =~ "not deleted"
    end

    test "restore refuses when a live tag reclaimed the slug", %{user: user, ws: ws, tag: tag} do
      {:ok, _} = Tags.delete(tag, user.id)
      {:ok, _} = Tags.create(ws.id, "deploys", "The new deploys.", user.id)

      assert {:error, :slug_taken} =
               Tags.restore(Tags.get_deleted(ws.id, "deploys"), user.id)
    end

    test "scope member order (sort_key) survives edits", %{user: user, ws: ws} do
      {:ok, a} = Tags.create(ws.id, "phase:todo", "Next up.", user.id, sort_key: "phase:1")
      {:ok, _b} = Tags.create(ws.id, "phase:done", "Shipped.", user.id, sort_key: "phase:2")

      # Recolor the FIRST member. The new version row must carry the
      # sort_key, so column order must not change.
      {:ok, _} = Tags.edit(a, %{color: "#3b82f6"}, user.id)

      assert Tags.list_scope_members(ws.id, "phase") == ["phase:todo", "phase:done"]

      # And a sort_key edit reorders: push todo after done.
      {:ok, _} = Tags.edit(Tags.get(ws.id, "phase:todo"), %{sort_key: "phase:3"}, user.id)
      assert Tags.list_scope_members(ws.id, "phase") == ["phase:done", "phase:todo"]
    end
  end

  describe "house model on docs" do
    test "editing a doc supersedes without touching deleted_at", %{user: user, ws: ws} do
      doc = Fixtures.doc_fixture(ws, user, title: "Doc")

      ops = [
        %{
          "op" => "append_block",
          "block" => %{"type" => "paragraph", "content" => [%{"text" => "v2"}]}
        }
      ]

      {:ok, _v2} =
        Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])

      old = Repo.get!(Aveline.Docs.Doc, doc.id)
      assert old.superseded
      assert old.deleted_at == nil
      assert old.deleted_by_id == nil
    end

    test "delete/restore round-trips; superseded history is not restorable", %{
      user: user,
      ws: ws
    } do
      doc = Fixtures.doc_fixture(ws, user, title: "Doc")
      {:ok, _} = Docs.soft_delete(Docs.get_current_by_slug(ws.id, doc.slug), user.id)
      assert Docs.get_current_by_slug(ws.id, doc.slug) == nil

      {:ok, restored} = Docs.restore(doc.base_doc_id, user.id)
      assert restored.deleted_at == nil

      # Restoring a live doc → not_user_deleted.
      assert {:error, :not_user_deleted} = Docs.restore(doc.base_doc_id, user.id)
    end
  end

  describe "list_with_stats/1" do
    test "counts live docs only — superseded versions don't inflate tag counts", %{
      user: user,
      ws: ws
    } do
      doc = Fixtures.doc_fixture(ws, user, title: "Doc", tags: ["deploys"])

      ops = [
        %{"op" => "append_block", "block" => %{"type" => "paragraph", "content" => [%{"text" => "v2"}]}}
      ]

      {:ok, v2} =
        Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])

      {:ok, _v3} =
        Docs.apply_ops(v2, ops, %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])

      %{count: count} =
        ws.id |> Tags.list_with_stats() |> Enum.find(&(&1.tag.slug == "deploys"))

      assert count == 1
    end
  end
end
