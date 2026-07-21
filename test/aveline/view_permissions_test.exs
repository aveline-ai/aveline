defmodule Aveline.ViewPermissionsTest do
  @moduledoc """
  View permissions: the doc model copied onto views. Private views
  vanish from every listing for non-shared members; the sidebar (pins)
  stays a team surface.
  """
  use Aveline.DataCase, async: true

  import Aveline.Fixtures

  alias Aveline.Views

  setup do
    owner = user_fixture()
    other = user_fixture()
    ws = workspace_fixture(owner)
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)
    {:ok, view} = Views.create(ws.id, "my-daily", "What I check every morning.", %{}, owner.id)

    %{owner: owner, other: other, ws: ws, view: view}
  end

  test "ownership is the creator and survives edits by others", %{
    owner: owner,
    other: other,
    view: view
  } do
    assert view.owner_id == owner.id

    {:ok, v2} = Views.edit(view, %{description: "Edited by someone else entirely."}, other.id)
    assert v2.owner_id == owner.id
    assert v2.created_by_id == other.id
  end

  test "private views hide from listings, shares reopen them", %{
    owner: owner,
    other: other,
    ws: ws,
    view: view
  } do
    {:ok, view} = Views.set_visibility(view, "private", owner.id)

    names = fn viewer -> Views.list_for_workspace(ws.id, viewer: viewer) |> Enum.map(& &1.name) end

    assert "my-daily" in names.(owner.id)
    refute "my-daily" in names.(other.id)
    refute "my-daily" in (Views.list_for_workspace(ws.id) |> Enum.map(& &1.name))

    {:ok, _} = Views.share_view(view, other.id, "viewer", owner.id)
    assert "my-daily" in names.(other.id)
    assert Views.member_can_use?(view, other.id)
    refute Views.member_can_edit?(view, other.id)

    {:ok, share} = Views.share_view(view, other.id, "editor", owner.id)
    assert share.role == "editor"
    assert Views.member_can_edit?(view, other.id)

    {:ok, _} = Views.unshare_view(view, other.id, owner.id)
    refute "my-daily" in names.(other.id)
  end

  test "only the owner changes visibility or shares", %{other: other, view: view} do
    assert {:error, msg} = Views.set_visibility(view, "private", other.id)
    assert msg =~ "owner"

    assert {:error, msg} = Views.share_view(view, other.id, "viewer", other.id)
    assert msg =~ "owner"
  end

  test "pin is universal: private views pin into only their audience's sidebars", %{
    owner: owner,
    other: other,
    ws: ws,
    view: view
  } do
    {:ok, view} = Views.set_visibility(view, "private", owner.id)
    {:ok, _} = Views.set_pinned(view, true)

    assert Enum.map(Views.sidebar_sections(ws.id, owner.id).yours, & &1.name) == ["my-daily"]
    assert Views.sidebar_sections(ws.id, other.id).shared == []

    {:ok, _} = Views.share_view(view, other.id, "viewer", owner.id)
    assert Enum.map(Views.sidebar_sections(ws.id, other.id).shared, & &1.name) == ["my-daily"]
  end

  test "sidebar sections: team pins, yours, shared with you", %{
    owner: owner,
    other: other,
    ws: ws,
    view: view
  } do
    {:ok, team} = Views.create(ws.id, "tickets-board", "The team ticket board.", %{}, other.id)
    {:ok, _} = Views.set_pinned(team, true)

    {:ok, view} = Views.set_visibility(view, "private", owner.id)
    {:ok, view} = Views.set_pinned(view, true)
    {:ok, _} = Views.share_view(view, other.id, "viewer", owner.id)

    owner_sections = Views.sidebar_sections(ws.id, owner.id)
    assert Enum.map(owner_sections.team, & &1.name) == ["tickets-board"]
    assert Enum.map(owner_sections.yours, & &1.name) == ["my-daily"]
    assert owner_sections.shared == []

    other_sections = Views.sidebar_sections(ws.id, other.id)
    assert Enum.map(other_sections.team, & &1.name) == ["tickets-board"]
    assert other_sections.yours == []
    assert Enum.map(other_sections.shared, & &1.name) == ["my-daily"]
  end

  test "visibility and owner carry across versions", %{owner: owner, view: view} do
    {:ok, view} = Views.set_visibility(view, "private", owner.id)
    {:ok, v2} = Views.edit(view, %{description: "Still my private daily view."}, owner.id)

    assert v2.visibility == "private"
    assert v2.owner_id == owner.id
    assert v2.version_number == view.version_number + 1
  end
end
