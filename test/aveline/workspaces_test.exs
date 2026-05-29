defmodule Aveline.WorkspacesTest do
  use Aveline.DataCase, async: true

  alias Aveline.Workspaces

  import Aveline.Fixtures

  test "create_workspace happy path" do
    u = user_fixture()

    assert {:ok, ws} =
             Workspaces.create_workspace(%{
               "slug" => "stable-pod",
               "name" => "Stable Pod",
               "created_by_id" => u.id
             })

    assert ws.slug == "stable-pod"
  end

  test "rejects invalid slug" do
    u = user_fixture()

    assert {:error, cs} =
             Workspaces.create_workspace(%{
               "slug" => "Bad Slug",
               "name" => "x",
               "created_by_id" => u.id
             })

    assert errors_on(cs).slug != []
  end

  test "member?/2 and ensure_member" do
    u = user_fixture()
    other = user_fixture()
    ws = workspace_fixture(u)

    assert Workspaces.member?(ws.id, u.id)
    refute Workspaces.member?(ws.id, other.id)

    {:ok, _} = Workspaces.ensure_member(ws.id, other.id)
    assert Workspaces.member?(ws.id, other.id)
  end

  test "soft-delete excludes from base_query" do
    u = user_fixture()
    ws = workspace_fixture(u)
    {:ok, _} = Workspaces.soft_delete_workspace(ws, u.id)
    refute Workspaces.get_active_by_slug(ws.slug)
  end
end
