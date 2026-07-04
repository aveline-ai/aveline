defmodule Aveline.ScopedTagsBoardTest do
  use Aveline.DataCase, async: false

  alias Aveline.Docs
  alias Aveline.Fixtures
  alias Aveline.Tags

  setup do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)

    for {slug, desc} <- [
          {"feature-x", "The feature-x work."},
          {"status:todo", "Status: next up."},
          {"status:doing", "Status: in flight."},
          {"status:done", "Status: shipped."}
        ] do
      {:ok, _} = Tags.create(ws.id, slug, desc, user.id)
    end

    %{user: user, ws: ws}
  end

  describe "scoped tag model" do
    test "scope_of / value_of" do
      assert Tags.scope_of("status:todo") == "status"
      assert Tags.scope_of("runbook") == nil
      assert Tags.value_of("status:todo") == "todo"
      assert Tags.value_of("runbook") == "runbook"
    end

    test "scoped slugs validate; malformed ones don't", %{user: user, ws: ws} do
      assert {:ok, _} = Tags.create(ws.id, "priority:p1", "Priority one.", user.id)
      assert {:error, _} = Tags.create(ws.id, "a:b:c", "Two colons.", user.id)
      assert {:error, _} = Tags.create(ws.id, ":todo", "Empty scope.", user.id)
      assert {:error, _} = Tags.create(ws.id, "status:", "Empty value.", user.id)
    end

    test "scope members come back in creation order", %{ws: ws} do
      assert Tags.list_scope_members(ws.id, "status") ==
               ["status:todo", "status:doing", "status:done"]
    end

    test "a doc can't carry two tags from one scope", %{user: user, ws: ws} do
      assert {:error, {:tag_scope_conflict, "status", tags}} =
               Docs.create_doc(%{
                 workspace_id: ws.id,
                 owner_id: user.id,
                 actor_user_id: user.id,
                 actor_type: "agent",
                 title: "Contradiction",
                 tags: ["feature-x", "status:todo", "status:done"],
                 blocks: []
               })

      assert tags == ["status:done", "status:todo"]
    end

    test "tags from different scopes coexist", %{user: user, ws: ws} do
      {:ok, _} = Tags.create(ws.id, "priority:p1", "Priority one.", user.id)

      assert {:ok, _} =
               Docs.create_doc(%{
                 workspace_id: ws.id,
                 owner_id: user.id,
                 actor_user_id: user.id,
                 actor_type: "agent",
                 title: "Multi-dimensional",
                 tags: ["feature-x", "status:todo", "priority:p1"],
                 blocks: []
               })
    end
  end

  describe "board block" do
    defp create_board(ws, user, tags \\ ["feature-x"], by \\ "status") do
      Docs.create_doc(%{
        workspace_id: ws.id,
        owner_id: user.id,
        actor_user_id: user.id,
        actor_type: "agent",
        title: "Feature X board",
        blocks: [%{"type" => "board", "tags" => tags, "by" => by}],
        intent: "test board"
      })
    end

    defp create_card(ws, user, title, tags) do
      Fixtures.doc_fixture(ws, user, title: title, tags: tags)
    end

    test "board over unknown filter tags is rejected", %{user: user, ws: ws} do
      assert {:error, {:unknown_tags, ["nope"]}} = create_board(ws, user, ["nope"])
    end

    test "enrichment computes columns and cards", %{user: user, ws: ws} do
      create_card(ws, user, "Card todo", ["feature-x", "status:todo"])
      create_card(ws, user, "Card done", ["feature-x", "status:done"])
      create_card(ws, user, "Card unstatused", ["feature-x"])
      create_card(ws, user, "Unrelated", ["status:todo"])

      {:ok, board} = create_board(ws, user)
      [%{"view" => view}] = Docs.enrich_blocks(board.blocks, ws.id)

      assert view["columns"] == ["status:todo", "status:doing", "status:done"]

      by_title = Map.new(view["cards"], &{&1["title"], &1["column"]})

      assert by_title == %{
               "Card todo" => "status:todo",
               "Card done" => "status:done",
               "Card unstatused" => nil
             }
    end

    test "echoed view is stripped when a block round-trips", %{user: user, ws: ws} do
      assert {:ok, doc} =
               Docs.create_doc(%{
                 workspace_id: ws.id,
                 owner_id: user.id,
                 actor_user_id: user.id,
                 actor_type: "agent",
                 title: "Forged view",
                 blocks: [
                   %{
                     "type" => "board",
                     "tags" => ["feature-x"],
                     "by" => "status",
                     "view" => %{"cards" => [%{"title" => "FORGED"}]}
                   }
                 ]
               })

      [block] = doc.blocks
      refute Map.has_key?(block, "view")
    end

    test "list_current has: filters by structural kind", %{user: user, ws: ws} do
      plain = Fixtures.doc_fixture(ws, user, title: "Plain")
      {:ok, board} = create_board(ws, user)

      trail =
        Fixtures.doc_fixture(ws, user,
          title: "Trail",
          blocks: [%{"type" => "doc_link", "doc" => plain.slug}]
        )

      slugs = fn opts -> ws.id |> Docs.list_current(opts) |> Enum.map(& &1.slug) |> Enum.sort() end

      assert slugs.(has: ["board"]) == [board.slug]
      assert slugs.(has: ["links"]) == [trail.slug]
      assert slugs.(has: ["bogus"]) == slugs.(has: [])
    end

    test "board block shape is validated", %{user: user, ws: ws} do
      assert {:error, msg} = create_board(ws, user, [])
      assert msg =~ "non-empty"

      assert {:error, msg} = create_board(ws, user, ["feature-x"], "not:a:scope")
      assert msg =~ "board.by"
    end
  end
end
