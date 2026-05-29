defmodule Aveline.ItemsTest do
  use Aveline.DataCase, async: true

  alias Aveline.Items

  import Aveline.Fixtures

  setup do
    user = user_fixture()
    ws = workspace_fixture(user)
    {:ok, user: user, ws: ws}
  end

  describe "create_item/1" do
    test "happy path with explicit slug", %{user: u, ws: w} do
      assert {:ok, item} =
               Items.create_item(%{
                 "workspace_id" => w.id,
                 "owner_id" => u.id,
                 "created_by_id" => u.id,
                 "created_via" => "cli",
                 "title" => "Hello",
                 "slug" => "hello",
                 "tags" => ["oncall", "infra"]
               })

      assert item.slug == "hello"
      assert item.tags == ["oncall", "infra"]
    end

    test "auto-derives slug from title", %{user: u, ws: w} do
      assert {:ok, item} =
               Items.create_item(%{
                 "workspace_id" => w.id,
                 "owner_id" => u.id,
                 "created_by_id" => u.id,
                 "created_via" => "cli",
                 "title" => "Oncall Rotation!"
               })

      assert item.slug == "oncall-rotation"
    end

    test "rejects when slug cannot be derived", %{user: u, ws: w} do
      assert {:error, cs} =
               Items.create_item(%{
                 "workspace_id" => w.id,
                 "owner_id" => u.id,
                 "created_by_id" => u.id,
                 "created_via" => "cli",
                 "title" => "🔥🔥🔥"
               })

      assert "could not derive slug from title" in errors_on(cs).slug
    end

    test "rejects invalid tags", %{user: u, ws: w} do
      assert {:error, cs} =
               Items.create_item(%{
                 "workspace_id" => w.id,
                 "owner_id" => u.id,
                 "created_by_id" => u.id,
                 "created_via" => "cli",
                 "title" => "Foo",
                 "tags" => ["bad tag!"]
               })

      assert "tag_invalid" in errors_on(cs).tags
    end

    test "rejects too many tags", %{user: u, ws: w} do
      tags = for n <- 1..17, do: "tag#{n}"

      assert {:error, cs} =
               Items.create_item(%{
                 "workspace_id" => w.id,
                 "owner_id" => u.id,
                 "created_by_id" => u.id,
                 "created_via" => "cli",
                 "title" => "Foo",
                 "tags" => tags
               })

      assert errors_on(cs).tags != []
    end

    test "slug uniqueness scoped to workspace (active)", %{user: u, ws: w} do
      _ = item_fixture(w, u, %{title: "Dup", slug: "dup"})

      assert {:error, cs} =
               Items.create_item(%{
                 "workspace_id" => w.id,
                 "owner_id" => u.id,
                 "created_by_id" => u.id,
                 "created_via" => "cli",
                 "title" => "Dup",
                 "slug" => "dup"
               })

      assert errors_on(cs).slug != []
    end
  end

  describe "list_items/2" do
    test "excludes soft-deleted, restore re-includes", %{user: u, ws: w} do
      item = item_fixture(w, u, %{title: "x", slug: "x"})
      assert Items.list_items(w.id) |> Enum.map(& &1.id) == [item.id]

      {:ok, _} = Items.soft_delete_item(item, u.id)
      assert Items.list_items(w.id) == []

      reloaded = Items.get_by_slug(w.id, "x")
      {:ok, _} = Items.restore_item(reloaded)
      assert Items.list_items(w.id) |> Enum.map(& &1.id) == [item.id]
    end

    test "tag filtering ⊇ semantics", %{user: u, ws: w} do
      a = item_fixture(w, u, %{title: "a", tags: ["oncall", "infra"]})
      _b = item_fixture(w, u, %{title: "b", tags: ["oncall"]})
      _c = item_fixture(w, u, %{title: "c", tags: ["infra"]})

      ids = Items.list_items(w.id, tags: ["oncall", "infra"]) |> Enum.map(& &1.id)
      assert ids == [a.id]
    end

    test "pinned filter", %{user: u, ws: w} do
      pinned = item_fixture(w, u, %{title: "p", pinned: true})
      _ = item_fixture(w, u, %{title: "u"})

      assert Items.list_items(w.id, pinned: true) |> Enum.map(& &1.id) == [pinned.id]
    end
  end
end
