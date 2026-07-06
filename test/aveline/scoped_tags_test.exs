defmodule Aveline.ScopedTagsTest do
  use Aveline.DataCase, async: false

  alias Aveline.Docs
  alias Aveline.Fixtures
  alias Aveline.Tags

  setup do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)

    for {slug, desc, sort_key} <- [
          {"feature-x", "The feature-x work.", nil},
          {"lane:todo", "Lane: next up.", "lane:1"},
          {"lane:doing", "Lane: in flight.", "lane:2"},
          {"lane:done", "Lane: shipped.", "lane:3"}
        ] do
      {:ok, _} = Tags.create(ws.id, slug, desc, user.id, sort_key: sort_key)
    end

    %{user: user, ws: ws}
  end

  describe "scoped tag model" do
    test "scope_of / value_of" do
      assert Tags.scope_of("lane:todo") == "lane"
      assert Tags.scope_of("runbook") == nil
      assert Tags.value_of("lane:todo") == "todo"
      assert Tags.value_of("runbook") == "runbook"
    end

    test "scoped slugs validate; malformed ones don't", %{user: user, ws: ws} do
      assert {:ok, _} = Tags.create(ws.id, "priority:p1", "Priority one.", user.id)
      assert {:error, _} = Tags.create(ws.id, "a:b:c", "Two colons.", user.id)
      assert {:error, _} = Tags.create(ws.id, ":todo", "Empty scope.", user.id)
      assert {:error, _} = Tags.create(ws.id, "status:", "Empty value.", user.id)
    end

    test "scope members come back in sort-key order", %{ws: ws} do
      assert Tags.list_scope_members(ws.id, "lane") ==
               ["lane:todo", "lane:doing", "lane:done"]
    end

    test "a doc can't carry two tags from one scope", %{user: user, ws: ws} do
      assert {:error, {:tag_scope_conflict, "lane", tags}} =
               Docs.create_doc(%{
                 workspace_id: ws.id,
                 owner_id: user.id,
                 actor_user_id: user.id,
                 actor_type: "agent",
                 title: "Contradiction",
                 tags: ["feature-x", "lane:todo", "lane:done"],
                 blocks: []
               })

      assert tags == ["lane:done", "lane:todo"]
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
                 tags: ["feature-x", "lane:todo", "priority:p1"],
                 blocks: []
               })
    end
  end
end
