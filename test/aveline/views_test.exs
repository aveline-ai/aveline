defmodule Aveline.ViewsTest do
  use Aveline.DataCase, async: false

  alias Aveline.Fixtures
  alias Aveline.Views

  defp setup_ws do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    %{user: user, ws: ws}
  end

  test "create validates config against the workspace" do
    %{user: user, ws: ws} = setup_ws()

    # Template tags exist (ticket, status scope) — valid kanban view.
    {:ok, view} =
      Views.create(ws.id, "tickets", "All open work by status.", %{
        "tags" => ["ticket"],
        "group_by" => "status"
      }, user.id)

    assert view.config == %{"tags" => ["ticket"], "group_by" => "status"}
    assert view.version_number == 1
    refute view.pinned

    # Unknown filter tag → the tags error.
    assert {:error, {:unknown_tags, ["ghost"]}} =
             Views.create(ws.id, "bad", "Filter typo.", %{"tags" => ["ghost"]}, user.id)

    # group_by with no members → view_invalid.
    assert {:error, :view_invalid, msg} =
             Views.create(ws.id, "bad2", "Empty scope.", %{"group_by" => "lane"}, user.id)

    assert msg =~ "lane"

    # Name is live-unique.
    assert {:error, %Ecto.Changeset{}} =
             Views.create(ws.id, "tickets", "Duplicate.", %{}, user.id)

    # Description required, name must be a slug.
    assert {:error, %Ecto.Changeset{}} = Views.create(ws.id, "ok-name", "", %{}, user.id)
    assert {:error, %Ecto.Changeset{}} = Views.create(ws.id, "Bad Name", "Valid description.", %{}, user.id)
  end

  test "edit mints versions on the same base; pin survives; delete/restore round-trips" do
    %{user: user, ws: ws} = setup_ws()
    {:ok, v1} = Views.create(ws.id, "tickets", "All open work.", %{"tags" => ["ticket"]}, user.id)
    {:ok, v1} = Views.set_pinned(v1, true)

    {:ok, v2} = Views.edit(v1, %{config: %{"tags" => ["ticket"], "group_by" => "status"}}, user.id)
    assert v2.version_number == 2
    assert v2.base_view_id == v1.base_view_id
    assert v2.pinned, "pin carries across versions"
    assert v2.config["group_by"] == "status"

    # Old row superseded, not deleted.
    old = Repo.get!(Aveline.Views.View, v1.id)
    assert old.superseded
    assert old.deleted_at == nil

    # Rename via edit.
    {:ok, v3} = Views.edit(v2, %{name: "work"}, user.id)
    assert v3.name == "work"
    assert Views.get_current_by_name(ws.id, "tickets") == nil
    assert Views.get_current_by_name(ws.id, "work")

    {:ok, _} = Views.delete(v3, user.id)
    assert Views.get_current_by_name(ws.id, "work") == nil
    assert Views.list_pinned(ws.id) == []

    {:ok, restored} = Views.restore(ws.id, "work")
    assert restored.deleted_at == nil
    assert [%{name: "work"}] = Views.list_pinned(ws.id)
  end

  test "list_for_workspace orders pinned first, then name" do
    %{user: user, ws: ws} = setup_ws()
    {:ok, _a} = Views.create(ws.id, "alpha", "First alphabetically.", %{}, user.id)
    {:ok, z} = Views.create(ws.id, "zulu", "Last alphabetically.", %{}, user.id)
    {:ok, _} = Views.set_pinned(z, true)

    assert ["zulu", "alpha"] = ws.id |> Views.list_for_workspace() |> Enum.map(& &1.name)
  end

  test "safe_map shape" do
    %{user: user, ws: ws} = setup_ws()
    {:ok, view} = Views.create(ws.id, "tickets", "All open work.", %{"tags" => ["ticket"]}, user.id)

    assert %{
             "name" => "tickets",
             "description" => "All open work.",
             "config" => %{"tags" => ["ticket"]},
             "pinned" => false,
             "version_number" => 1
           } = Views.safe_map(view)
  end
end
