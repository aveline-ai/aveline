defmodule Aveline.ViewsTest do
  use Aveline.DataCase, async: true

  alias Aveline.Views

  import Aveline.Fixtures

  test "create and matching_items intersects tags" do
    u = user_fixture()
    ws = workspace_fixture(u)
    _ = item_fixture(ws, u, %{title: "a", tags: ["oncall", "infra"]})
    _ = item_fixture(ws, u, %{title: "b", tags: ["oncall"]})

    {:ok, view} =
      Views.create_view(%{
        "workspace_id" => ws.id,
        "slug" => "oncall-infra",
        "name" => "Oncall + Infra",
        "tag_filter" => ["oncall", "infra"],
        "created_by_id" => u.id
      })

    items = Views.matching_items(view)
    assert length(items) == 1
    assert hd(items).title == "a"
  end

  test "rejects invalid tag_filter" do
    u = user_fixture()
    ws = workspace_fixture(u)

    assert {:error, cs} =
             Views.create_view(%{
               "workspace_id" => ws.id,
               "slug" => "bad",
               "name" => "bad",
               "tag_filter" => ["bad tag"],
               "created_by_id" => u.id
             })

    assert "tag_invalid" in errors_on(cs).tag_filter
  end

  test "soft delete excludes from list" do
    u = user_fixture()
    ws = workspace_fixture(u)
    v = view_fixture(ws, u)
    {:ok, _} = Views.soft_delete_view(v, u.id)
    assert Views.list_views(ws.id) == []
  end
end
