defmodule Aveline.OrientationDocTest do
  use Aveline.DataCase, async: false

  alias Aveline.Docs
  alias Aveline.Fixtures

  setup do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    %{user: user, ws: ws}
  end

  test "every new workspace gets the orientation doc, pinned at the well-known slug", %{ws: ws} do
    doc = Docs.get_orientation(ws.id)
    assert doc
    assert doc.slug == Docs.orientation_slug()
    assert doc.pinned
    assert doc.title == "How we use Aveline here"
  end

  test "the orientation doc cannot be soft-deleted", %{user: user, ws: ws} do
    doc = Docs.get_orientation(ws.id)
    assert {:error, :orientation_undeletable} = Docs.soft_delete(doc, user.id)
    assert Docs.get_orientation(ws.id)
  end

  test "the orientation doc cannot be unpinned", %{user: user, ws: ws} do
    doc = Docs.get_orientation(ws.id)
    assert {:error, :orientation_pin_required} = Docs.set_pinned(doc, false, user.id)
  end

  test "pin budget: the workspace caps at #{Aveline.Docs.pin_limit()} pinned docs", %{
    user: user,
    ws: ws
  } do
    # Orientation holds slot 1; fill the remaining slots.
    free = Docs.pin_limit() - 1

    docs =
      for i <- 1..free do
        Fixtures.doc_fixture(ws, user, title: "Pin #{i}", pinned: true)
      end

    assert length(docs) == free

    # Slot 7 — via create_doc...
    assert {:error, :pin_limit_reached} =
             Docs.create_doc(%{
               workspace_id: ws.id,
               owner_id: user.id,
               actor_user_id: user.id,
               actor_type: "agent",
               title: "One too many",
               pinned: true,
               blocks: []
             })

    # ...and via set_pinned on an existing unpinned doc.
    loose = Fixtures.doc_fixture(ws, user, title: "Loose")
    assert {:error, :pin_limit_reached} = Docs.set_pinned(loose, true, user.id)

    # Unpinning one frees the slot.
    assert {:ok, _} = Docs.set_pinned(hd(docs), false, user.id)
    assert {:ok, _} = Docs.set_pinned(loose, true, user.id)
  end

  test "the orientation doc is editable like any other doc", %{user: user, ws: ws} do
    doc = Docs.get_orientation(ws.id)

    ops = [
      %{
        "op" => "append_block",
        "block" => %{"type" => "paragraph", "content" => [%{"text" => "we ship on fridays"}]}
      }
    ]

    assert {:ok, v2} =
             Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"},
               intent: "fill in conventions",
               dispositions: []
             )

    assert v2.version_number == 2
  end

  test "orientation doc accepts doc_link blocks", %{user: user, ws: ws} do
    target = Fixtures.doc_fixture(ws, user, slug: "read-me-first", title: "Read me first")
    doc = Docs.get_orientation(ws.id)

    ops = [%{"op" => "append_block", "block" => %{"type" => "doc_link", "doc" => "read-me-first"}}]

    assert {:ok, v2} =
             Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"},
               intent: "add first stop",
               dispositions: []
             )

    assert Enum.any?(v2.blocks, &(&1["type"] == "doc_link" and &1["doc_id"] == target.base_doc_id))
  end
end
