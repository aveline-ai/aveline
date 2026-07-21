defmodule Aveline.ViewPermissionsTest do
  @moduledoc """
  View buckets: views live in exactly one bucket (Team / personal /
  project) and buckets are the unit of sharing. The core promise: a
  view outside your buckets doesn't exist for you, on any surface.
  """
  use Aveline.DataCase, async: true

  import Aveline.Fixtures

  alias Aveline.Views

  setup do
    owner = user_fixture()
    other = user_fixture()
    outsider = user_fixture()
    ws = workspace_fixture(owner)
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)

    %{owner: owner, other: other, outsider: outsider, ws: ws}
  end

  test "views default into the team bucket and everyone sees them", %{
    owner: owner,
    other: other,
    ws: ws
  } do
    {:ok, view} = Views.create(ws.id, "tickets-board", "The team ticket board.", %{}, owner.id)

    assert view.bucket_id == Views.ensure_team_bucket(ws.id).id

    names = fn viewer -> Views.list_for_workspace(ws.id, viewer: viewer) |> Enum.map(& &1.name) end
    assert "tickets-board" in names.(owner.id)
    assert "tickets-board" in names.(other.id)
  end

  test "personal-bucket views exist only for their owner", %{owner: owner, other: other, ws: ws} do
    personal = Views.ensure_personal_bucket(ws.id, owner.id)

    {:ok, _} =
      Views.create(ws.id, "my-daily", "What I check every morning.", %{}, owner.id,
        bucket: personal
      )

    names = fn viewer -> Views.list_for_workspace(ws.id, viewer: viewer) |> Enum.map(& &1.name) end
    assert "my-daily" in names.(owner.id)
    refute "my-daily" in names.(other.id)
    # No viewer fails closed.
    refute "my-daily" in (Views.list_for_workspace(ws.id) |> Enum.map(& &1.name))

    view = Views.get_current_by_name(ws.id, "my-daily")
    assert Views.member_can_use?(view, owner.id)
    refute Views.member_can_use?(view, other.id)
  end

  test "project buckets share every view with members, present and future", %{
    owner: owner,
    other: other,
    outsider: outsider,
    ws: ws
  } do
    {:ok, bucket} = Views.create_bucket(ws.id, "launch", owner.id)

    {:ok, _} =
      Views.create(ws.id, "launch-tickets", "Launch project tickets.", %{}, owner.id,
        bucket: bucket
      )

    names = fn viewer -> Views.list_for_workspace(ws.id, viewer: viewer) |> Enum.map(& &1.name) end

    # Before membership: invisible.
    refute "launch-tickets" in names.(other.id)

    {:ok, _} = Views.add_bucket_member(bucket, other.id, owner.id)
    assert "launch-tickets" in names.(other.id)

    # Future views arrive automatically with the bucket.
    {:ok, _} =
      Views.create(ws.id, "launch-metrics", "Launch metrics slice.", %{}, owner.id,
        bucket: bucket
      )

    assert "launch-metrics" in names.(other.id)

    # Removal closes the whole bucket at once.
    {:ok, _} = Views.remove_bucket_member(bucket, other.id, owner.id)
    refute "launch-tickets" in names.(other.id)
    refute "launch-metrics" in names.(other.id)

    # Non-workspace-members can't be added at all.
    assert {:error, msg} = Views.add_bucket_member(bucket, outsider.id, owner.id)
    assert msg =~ "not a member"
  end

  test "workspace-visible buckets reach everyone, current and future", %{
    owner: owner,
    other: other,
    ws: ws
  } do
    {:ok, bucket} = Views.create_bucket(ws.id, "launch", owner.id, visibility: "workspace")

    {:ok, _} =
      Views.create(ws.id, "launch-tickets", "Launch project tickets.", %{}, owner.id,
        bucket: bucket
      )

    names = fn viewer -> Views.list_for_workspace(ws.id, viewer: viewer) |> Enum.map(& &1.name) end

    # Everyone sees it without any membership row — including a member
    # who joins after the bucket existed.
    assert "launch-tickets" in names.(other.id)

    late = user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, late.id)
    assert "launch-tickets" in names.(late.id)

    # Its sidebar section appears for them too (once a view is pinned).
    view = Views.get_current_by_name(ws.id, "launch-tickets")
    {:ok, _} = Views.set_pinned(view, true)
    assert [%{bucket: %{name: "launch"}}] = Views.sidebar_sections(ws.id, late.id).buckets

    # Flip back private: only owner + members again. Owner only flips.
    assert {:error, msg} = Views.set_bucket_visibility(bucket, "private", other.id)
    assert msg =~ "owner"

    {:ok, bucket} = Views.set_bucket_visibility(bucket, "private", owner.id)
    refute "launch-tickets" in names.(late.id)
    assert "launch-tickets" in names.(owner.id)

    # Team and personal visibilities are fixed by definition.
    team = Views.ensure_team_bucket(ws.id)
    assert {:error, msg} = Views.set_bucket_visibility(team, "private", owner.id)
    assert msg =~ "only project buckets"

    personal = Views.ensure_personal_bucket(ws.id, owner.id)
    assert {:error, _} = Views.set_bucket_visibility(personal, "workspace", owner.id)
    assert bucket.visibility == "private"
  end

  test "bucket management is owner-only; team and personal take no members", %{
    owner: owner,
    other: other,
    ws: ws
  } do
    {:ok, bucket} = Views.create_bucket(ws.id, "launch", owner.id)

    assert {:error, msg} = Views.add_bucket_member(bucket, other.id, other.id)
    assert msg =~ "owner"

    team = Views.ensure_team_bucket(ws.id)
    assert {:error, msg} = Views.add_bucket_member(team, other.id, owner.id)
    assert msg =~ "everyone"

    personal = Views.ensure_personal_bucket(ws.id, owner.id)
    assert {:error, _} = Views.add_bucket_member(personal, other.id, owner.id)
  end

  test "reserved bucket names are rejected and project names are unique", %{owner: owner, ws: ws} do
    assert {:error, msg} = Views.create_bucket(ws.id, "team", owner.id)
    assert msg =~ "reserved"

    assert {:error, msg} = Views.create_bucket(ws.id, "personal-alice", owner.id)
    assert msg =~ "reserved"

    {:ok, _} = Views.create_bucket(ws.id, "launch", owner.id)
    assert {:error, %Ecto.Changeset{}} = Views.create_bucket(ws.id, "launch", owner.id)
  end

  test "move_view: owner only, into buckets they can use; bucket carries across versions", %{
    owner: owner,
    other: other,
    ws: ws
  } do
    {:ok, view} = Views.create(ws.id, "my-daily", "What I check every morning.", %{}, owner.id)
    personal = Views.ensure_personal_bucket(ws.id, owner.id)

    assert {:error, msg} = Views.move_view(view, personal, other.id)
    assert msg =~ "owner"

    other_personal = Views.ensure_personal_bucket(ws.id, other.id)
    assert {:error, msg} = Views.move_view(view, other_personal, owner.id)
    assert msg =~ "aren't in that bucket"

    {:ok, view} = Views.move_view(view, personal, owner.id)
    assert view.bucket_id == personal.id

    {:ok, v2} = Views.edit(view, %{description: "Still mine, still in my bucket."}, owner.id)
    assert v2.bucket_id == personal.id
    assert v2.owner_id == owner.id
  end

  test "empty project buckets delete, occupied ones refuse", %{owner: owner, ws: ws} do
    {:ok, bucket} = Views.create_bucket(ws.id, "launch", owner.id)

    {:ok, view} =
      Views.create(ws.id, "launch-tickets", "Launch project tickets.", %{}, owner.id,
        bucket: bucket
      )

    assert {:error, msg} = Views.delete_bucket(bucket, owner.id)
    assert msg =~ "views first"

    {:ok, _} = Views.move_view(view, Views.ensure_team_bucket(ws.id), owner.id)
    assert {:ok, _} = Views.delete_bucket(bucket, owner.id)
  end

  test "sidebar sections: team, yours, then one per project bucket; pin still gates", %{
    owner: owner,
    other: other,
    ws: ws
  } do
    {:ok, team_view} = Views.create(ws.id, "tickets-board", "The team ticket board.", %{}, other.id)
    {:ok, _} = Views.set_pinned(team_view, true)

    personal = Views.ensure_personal_bucket(ws.id, owner.id)

    {:ok, mine} =
      Views.create(ws.id, "my-daily", "What I check every morning.", %{}, owner.id,
        bucket: personal
      )

    {:ok, bucket} = Views.create_bucket(ws.id, "launch", other.id)
    {:ok, _} = Views.add_bucket_member(bucket, owner.id, other.id)

    {:ok, launch_view} =
      Views.create(ws.id, "launch-tickets", "Launch project tickets.", %{}, other.id,
        bucket: bucket
      )

    # Unpinned: sections stay empty of them.
    sections = Views.sidebar_sections(ws.id, owner.id)
    assert Enum.map(sections.team, & &1.name) == ["tickets-board"]
    assert sections.yours == []
    assert sections.buckets == []

    {:ok, _} = Views.set_pinned(mine, true)
    {:ok, _} = Views.set_pinned(launch_view, true)

    sections = Views.sidebar_sections(ws.id, owner.id)
    assert Enum.map(sections.yours, & &1.name) == ["my-daily"]
    assert [%{bucket: %{name: "launch"}, views: [%{name: "launch-tickets"}]}] = sections.buckets

    # A non-member of the launch bucket never sees its section.
    third = user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, third.id)
    sections = Views.sidebar_sections(ws.id, third.id)
    assert sections.buckets == []
    assert sections.yours == []
  end
end
