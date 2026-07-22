defmodule Aveline.DocPermissionsTest do
  @moduledoc """
  Doc permissions v1: private | workspace visibility, viewer/editor
  shares, one access rule. The core promise under test: a private doc
  never appears on any surface for a non-shared member, and
  inaccessible is indistinguishable from nonexistent.
  """
  use Aveline.DataCase, async: true

  import Aveline.Fixtures

  alias Aveline.Docs
  alias Aveline.Events

  setup do
    owner = user_fixture()
    other = user_fixture()
    outsider = user_fixture()
    ws = workspace_fixture(owner)
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)

    %{owner: owner, other: other, outsider: outsider, ws: ws}
  end

  describe "list_current viewer scoping" do
    test "private docs show for the owner, not for other members", %{
      owner: owner,
      other: other,
      ws: ws
    } do
      doc_fixture(ws, owner, title: "Team doc")
      doc_fixture(ws, owner, title: "Secret", visibility: "private")

      owner_titles = Docs.list_current(ws.id, viewer: owner.id) |> Enum.map(& &1.title)
      other_titles = Docs.list_current(ws.id, viewer: other.id) |> Enum.map(& &1.title)

      assert "Secret" in owner_titles
      assert "Team doc" in other_titles
      refute "Secret" in other_titles
    end

    test "omitting viewer fails closed", %{owner: owner, ws: ws} do
      doc_fixture(ws, owner, title: "Secret", visibility: "private")
      refute "Secret" in (Docs.list_current(ws.id) |> Enum.map(& &1.title))
    end

    test "a shared member sees the private doc", %{owner: owner, other: other, ws: ws} do
      doc = doc_fixture(ws, owner, title: "Secret", visibility: "private")
      {:ok, _} = Docs.share_doc(doc, other.id, "viewer", owner.id)

      assert "Secret" in (Docs.list_current(ws.id, viewer: other.id) |> Enum.map(& &1.title))
    end

    test "search cannot find unreadable docs", %{owner: owner, other: other, ws: ws} do
      doc_fixture(ws, owner, title: "Zanzibar planning", visibility: "private")

      assert Docs.list_current(ws.id, viewer: other.id, search: "zanzibar") == []
      refute Docs.list_current(ws.id, viewer: owner.id, search: "zanzibar") == []
    end
  end

  describe "member_can_read?/member_can_edit?" do
    test "viewer share reads but does not edit; editor share does both", %{
      owner: owner,
      other: other,
      ws: ws
    } do
      doc = doc_fixture(ws, owner, visibility: "private")

      refute Docs.member_can_read?(doc, other.id)
      refute Docs.member_can_edit?(doc, other.id)

      {:ok, _} = Docs.share_doc(doc, other.id, "viewer", owner.id)
      assert Docs.member_can_read?(doc, other.id)
      refute Docs.member_can_edit?(doc, other.id)

      # Re-share upserts the live row to editor.
      {:ok, share} = Docs.share_doc(doc, other.id, "editor", owner.id)
      assert share.role == "editor"
      assert Docs.member_can_edit?(doc, other.id)

      {:ok, _} = Docs.unshare_doc(doc, other.id, owner.id)
      refute Docs.member_can_read?(doc, other.id)
    end

    test "workspace docs stay readable and editable by any member", %{
      owner: owner,
      other: other,
      ws: ws
    } do
      doc = doc_fixture(ws, owner)
      assert Docs.member_can_read?(doc, other.id)
      assert Docs.member_can_edit?(doc, other.id)
    end
  end

  describe "set_visibility" do
    test "owner flips visibility in place without a new version", %{owner: owner, ws: ws} do
      doc = doc_fixture(ws, owner)

      {:ok, updated} = Docs.set_visibility(doc, "private", owner.id)
      assert updated.visibility == "private"
      assert updated.version_number == doc.version_number
    end

    test "non-owners cannot change visibility", %{owner: owner, other: other, ws: ws} do
      doc = doc_fixture(ws, owner)
      assert {:error, msg} = Docs.set_visibility(doc, "private", other.id)
      assert msg =~ "owner"
    end

    test "the orientation doc cannot go private", %{owner: owner, ws: ws} do
      orientation = Docs.get_orientation(ws.id)
      assert orientation.visibility == "workspace"
      assert {:error, msg} = Docs.set_visibility(orientation, "private", owner.id)
      assert msg =~ "orientation"
    end

    test "pinned docs cannot go private, private docs cannot be pinned", %{
      owner: owner,
      ws: ws
    } do
      pinned = doc_fixture(ws, owner)
      {:ok, pinned} = Docs.pin(pinned, 1, owner.id)
      assert {:error, msg} = Docs.set_visibility(pinned, "private", owner.id)
      assert msg =~ "unpin"

      secret = doc_fixture(ws, owner, visibility: "private")
      assert {:error, msg} = Docs.pin(secret, 2, owner.id)
      assert msg =~ "private"
    end

    test "visibility survives edits", %{owner: owner, ws: ws} do
      doc = doc_fixture(ws, owner, visibility: "private")

      {:ok, v2} =
        Docs.apply_ops(
          doc,
          [%{"op" => "append_block", "block" => %{"type" => "paragraph", "content" => [%{"text" => "more"}]}}],
          %{actor_user_id: owner.id, actor_type: "agent"},
          intent: "test edit"
        )

      assert v2.visibility == "private"
      assert v2.version_number == doc.version_number + 1
    end
  end

  describe "share_doc rules" do
    test "only the owner shares; targets must be members", %{
      owner: owner,
      other: other,
      outsider: outsider,
      ws: ws
    } do
      doc = doc_fixture(ws, owner, visibility: "private")

      assert {:error, msg} = Docs.share_doc(doc, other.id, "viewer", other.id)
      assert msg =~ "owner"

      assert {:error, msg} = Docs.share_doc(doc, outsider.id, "viewer", owner.id)
      assert msg =~ "member"

      assert {:error, msg} = Docs.share_doc(doc, owner.id, "viewer", owner.id)
      assert msg =~ "full access"
    end
  end

  describe "events feed" do
    test "a private doc's event trail is hidden from non-shared members", %{
      owner: owner,
      other: other,
      ws: ws
    } do
      doc = doc_fixture(ws, owner, title: "Secret", visibility: "private")

      Events.record(%{
        workspace_id: ws.id,
        actor: owner.id,
        actor_type: "agent",
        action: "doc_created",
        target_kind: "doc",
        target_id: doc.base_doc_id,
        target_slug: doc.slug,
        target_label: doc.title
      })

      owner_targets =
        Events.list_for_workspace(ws.id, viewer: owner.id) |> Enum.map(& &1.target_id)

      other_targets =
        Events.list_for_workspace(ws.id, viewer: other.id) |> Enum.map(& &1.target_id)

      assert doc.base_doc_id in owner_targets
      refute doc.base_doc_id in other_targets
    end

    test "comment events on a private doc hide too — no title leak via the feed", %{
      owner: owner,
      other: other,
      ws: ws
    } do
      doc = doc_fixture(ws, owner, title: "Secret", visibility: "private")

      {:ok, _comment} =
        Aveline.Comments.create_comment(%{
          "doc_id" => doc.id,
          "body" => "note to self",
          "actor_user_id" => owner.id,
          "actor_type" => "human"
        })

      labels = fn viewer ->
        Events.list_for_workspace(ws.id, viewer: viewer)
        |> Enum.filter(&(&1.target_kind == "comment"))
        |> Enum.map(& &1.target_label)
      end

      assert "Secret" in labels.(owner.id)
      refute "Secret" in labels.(other.id)

      # Comment events on workspace docs still flow to everyone.
      open_doc = doc_fixture(ws, owner, title: "Open doc")

      {:ok, _} =
        Aveline.Comments.create_comment(%{
          "doc_id" => open_doc.id,
          "body" => "hello team",
          "actor_user_id" => owner.id,
          "actor_type" => "human"
        })

      assert "Open doc" in labels.(other.id)
    end
  end

  describe "doc links" do
    test "links to unreadable docs render inaccessible without leaking the title", %{
      owner: owner,
      other: other,
      ws: ws
    } do
      secret = doc_fixture(ws, owner, title: "Secret target", visibility: "private")

      linking =
        doc_fixture(ws, owner,
          blocks: [%{"type" => "doc_link", "doc_id" => secret.base_doc_id}]
        )

      [for_other] = Docs.enrich_blocks(linking.blocks, ws.id, run_charts: false, viewer: other.id)
      assert for_other["target"] == %{"inaccessible" => true}

      [for_owner] = Docs.enrich_blocks(linking.blocks, ws.id, run_charts: false, viewer: owner.id)
      assert for_owner["target"]["title"] == "Secret target"
    end
  end
end
