defmodule Aveline.OrientationDocTest do
  use Aveline.DataCase, async: false

  alias Aveline.Docs
  alias Aveline.Fixtures

  setup do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    %{user: user, ws: ws}
  end

  test "every new workspace gets the recommended template tags", %{ws: ws} do
    slugs = Aveline.Tags.list_slugs(ws.id)

    for {slug, _desc, _color, _sort_key} <- Aveline.Workspaces.Template.tags() do
      assert slug in slugs
    end

    # Board columns work out of the box, in template order.
    assert Aveline.Tags.list_scope_members(ws.id, "status") ==
             ["status:backlog", "status:todo", "status:in-progress", "status:done", "status:cancelled"]
  end

  test "every new workspace gets exactly one orientation doc", %{ws: ws} do
    doc = Docs.get_orientation(ws.id)
    assert doc
    assert doc.orientation
    assert doc.title == "How we use Aveline here"
  end

  test "a second orientation doc is unrepresentable", %{user: user, ws: ws} do
    assert {:error, %Ecto.Changeset{} = cs} =
             Docs.create_doc(%{
               workspace_id: ws.id,
               owner_id: user.id,
               actor_user_id: user.id,
               actor_type: "human",
               orientation: true,
               title: "Impostor orientation",
               blocks: []
             })

    assert cs.errors != []
  end

  test "orientation survives edits", %{user: user, ws: ws} do
    doc = Docs.get_orientation(ws.id)

    ops = [
      %{
        "op" => "append_block",
        "block" => %{"type" => "paragraph", "content" => [%{"text" => "conventions"}]}
      }
    ]

    {:ok, v2} =
      Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])

    assert v2.orientation
    assert Docs.get_orientation(ws.id).id == v2.id
  end

  test "the orientation doc cannot be soft-deleted", %{user: user, ws: ws} do
    doc = Docs.get_orientation(ws.id)
    assert {:error, :orientation_undeletable} = Docs.soft_delete(doc, user.id)
    assert Docs.get_orientation(ws.id)
  end

  test "the orientation doc can't take a pin slot (it has its own card)", %{user: user, ws: ws} do
    doc = Docs.get_orientation(ws.id)
    assert {:error, msg} = Docs.pin(doc, 1, user.id)
    assert msg =~ "own card"
  end

  describe "pin slots" do
    test "explicit slot, auto-assign, occupancy, and the budget", %{user: user, ws: ws} do
      docs = for i <- 1..7, do: Fixtures.doc_fixture(ws, user, title: "Doc #{i}")
      [a, b, c | _rest] = docs

      # Explicit slot.
      assert {:ok, %{pin_slot: 3}} = Docs.pin(a, 3, user.id)

      # Occupied slot errors with the occupant — no silent displacement.
      assert {:error, {:pin_slot_taken, 3, occupant}} = Docs.pin(b, 3, user.id)
      assert occupant == a.slug

      # Auto-assign takes the lowest free slot.
      assert {:ok, %{pin_slot: 1}} = Docs.pin(b, nil, user.id)
      assert {:ok, %{pin_slot: 2}} = Docs.pin(c, nil, user.id)

      # Fill the rest; the 7th pin hits the budget.
      [d, e, f, g] = Enum.drop(docs, 3)
      assert {:ok, _} = Docs.pin(d, nil, user.id)
      assert {:ok, _} = Docs.pin(e, nil, user.id)
      assert {:ok, _} = Docs.pin(f, nil, user.id)
      assert {:error, :pin_limit_reached} = Docs.pin(g, nil, user.id)

      # list_pinned comes back in slot order.
      slots = ws.id |> Docs.list_pinned() |> Enum.map(& &1.pin_slot)
      assert slots == Enum.sort(slots)

      # Unpin frees the slot for the next pin.
      assert {:ok, %{pin_slot: nil}} = Docs.unpin(Docs.get_current_by_slug(ws.id, a.slug), user.id)
      assert {:ok, %{pin_slot: 3}} = Docs.pin(g, 3, user.id)
    end

    test "slot survives new versions; out-of-range and double-unpin rejected", %{
      user: user,
      ws: ws
    } do
      doc = Fixtures.doc_fixture(ws, user, title: "Slotted")
      assert {:ok, %{pin_slot: 2}} = Docs.pin(doc, 2, user.id)

      ops = [
        %{
          "op" => "append_block",
          "block" => %{"type" => "paragraph", "content" => [%{"text" => "edit"}]}
        }
      ]

      current = Docs.get_current_by_slug(ws.id, doc.slug)

      {:ok, v2} =
        Docs.apply_ops(current, ops, %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])

      assert v2.pin_slot == 2

      assert {:error, msg} = Docs.pin(v2, 9, user.id)
      assert msg =~ "between 1 and"

      assert {:ok, _} = Docs.unpin(v2, user.id)
      unpinned = Docs.get_current_by_slug(ws.id, doc.slug)
      assert {:error, "doc is not pinned"} = Docs.unpin(unpinned, user.id)
    end
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
