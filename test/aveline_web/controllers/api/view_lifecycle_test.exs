defmodule AvelineWeb.Api.ViewLifecycleTest do
  @moduledoc """
  Views + view-buckets over HTTP — integration coverage for the Gleam
  handlers (src/aveline/handlers/views.gleam, view_buckets.gleam) +
  CtxBuilder boundary. Behavior must match the pre-Gleam endpoints.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  setup %{conn: conn} do
    owner = user_fixture()
    other = user_fixture()
    ws = workspace_fixture(owner)
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)

    {_t, owner_token} = token_fixture(owner)
    {_t, other_token} = token_fixture(other)

    as = fn token ->
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
    end

    {:ok, owner_conn: as.(owner_token), other_conn: as.(other_token), ws: ws, owner: owner, other: other}
  end

  defp create_view(conn, ws, attrs) do
    post(conn, ~p"/api/workspaces/#{ws.slug}/views", attrs)
  end

  test "create defaults to the personal bucket; team is explicit", %{owner_conn: conn, ws: ws, owner: owner} do
    body =
      conn
      |> create_view(ws, %{"name" => " Mine ", "description" => "Just my things."})
      |> json_response(200)

    assert body["view"]["name"] == "mine"
    assert body["view"]["bucket"] == %{"kind" => "personal", "name" => "personal-#{owner.username}"}
    assert body["view"]["version_number"] == 1
    assert body["view"]["config"] == %{"tags" => []}
    refute body["view"]["pinned"]

    body =
      conn
      |> create_view(ws, %{"name" => "shared", "description" => "For everyone here.", "bucket" => "team"})
      |> json_response(200)

    assert body["view"]["bucket"] == %{"kind" => "team", "name" => "team"}
  end

  test "index shows only views whose bucket audience includes you", %{
    owner_conn: owner_conn,
    other_conn: other_conn,
    ws: ws
  } do
    owner_conn
    |> create_view(ws, %{"name" => "secret", "description" => "Owner's personal view."})
    |> json_response(200)

    owner_conn
    |> create_view(ws, %{"name" => "shared", "description" => "For everyone here.", "bucket" => "team"})
    |> json_response(200)

    names = fn conn ->
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/views")
      |> json_response(200)
      |> Map.fetch!("views")
      |> Enum.map(& &1["name"])
    end

    assert "secret" in names.(owner_conn)
    refute "secret" in names.(other_conn)
    assert "shared" in names.(other_conn)
  end

  test "personal views are invisible to others by name too", %{owner_conn: owner_conn, other_conn: other_conn, ws: ws} do
    owner_conn
    |> create_view(ws, %{"name" => "secret", "description" => "Owner's personal view."})
    |> json_response(200)

    assert other_conn
           |> patch(~p"/api/workspaces/#{ws.slug}/views/secret", %{"description" => "Hijacked but longer."})
           |> json_response(404)

    assert other_conn |> delete(~p"/api/workspaces/#{ws.slug}/views/secret") |> json_response(404)
  end

  test "update mints a version, merges config, keeps pin", %{owner_conn: conn, ws: ws} do
    conn
    |> create_view(ws, %{
      "name" => "tickets",
      "description" => "All open work.",
      "bucket" => "team",
      "config" => %{"tags" => ["ticket"], "group_by" => "status"}
    })
    |> json_response(200)

    conn |> post(~p"/api/workspaces/#{ws.slug}/views/tickets/pin") |> json_response(200)

    body =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/views/tickets", %{"config" => %{"sort" => "title"}})
      |> json_response(200)

    assert body["view"]["version_number"] == 2
    assert body["view"]["config"] == %{"tags" => ["ticket"], "group_by" => "status", "sort" => "title"}
    assert body["view"]["pinned"] == true
    # Parity quirk: the freshly minted row answers without its bucket.
    assert body["view"]["bucket"] == nil
  end

  test "config validation: unknown tags and empty group_by scope", %{owner_conn: conn, ws: ws} do
    body =
      conn
      |> create_view(ws, %{"name" => "bad", "description" => "Filter typo here.", "config" => %{"tags" => ["ghost"]}})
      |> json_response(422)

    assert body["error"]["code"] == "unknown_tags"

    body =
      conn
      |> create_view(ws, %{"name" => "bad2", "description" => "Empty scope here.", "config" => %{"group_by" => "lane"}})
      |> json_response(422)

    assert body["error"]["code"] == "view_invalid"
    assert body["error"]["message"] =~ "lane"
  end

  test "duplicate and invalid names are validation_failed", %{owner_conn: conn, ws: ws} do
    conn |> create_view(ws, %{"name" => "dup", "description" => "First one in."}) |> json_response(200)

    body = conn |> create_view(ws, %{"name" => "dup", "description" => "Second one out."}) |> json_response(422)
    assert body["error"]["code"] == "validation_failed"

    body = conn |> create_view(ws, %{"name" => "Bad Name", "description" => "Slugs only please."}) |> json_response(422)
    assert body["error"]["code"] == "validation_failed"
  end

  test "delete then restore round-trips; restoring twice is not_user_deleted", %{owner_conn: conn, ws: ws} do
    conn
    |> create_view(ws, %{"name" => "temp", "description" => "Soon to be gone.", "bucket" => "team"})
    |> json_response(200)

    assert conn |> delete(~p"/api/workspaces/#{ws.slug}/views/temp") |> json_response(200)

    body = conn |> post(~p"/api/workspaces/#{ws.slug}/views/temp/restore") |> json_response(200)
    assert body["view"]["name"] == "temp"
    # Parity quirk: restore answers without the bucket.
    assert body["view"]["bucket"] == nil

    body = conn |> post(~p"/api/workspaces/#{ws.slug}/views/temp/restore") |> json_response(422)
    assert body["error"]["code"] == "not_user_deleted"
  end

  test "pin and unpin update placement in place", %{owner_conn: conn, ws: ws} do
    conn
    |> create_view(ws, %{"name" => "pinme", "description" => "Sidebar candidate.", "bucket" => "team"})
    |> json_response(200)

    body = conn |> post(~p"/api/workspaces/#{ws.slug}/views/pinme/pin") |> json_response(200)
    assert body["view"]["pinned"] == true
    assert body["view"]["version_number"] == 1
    assert body["view"]["bucket"] == %{"kind" => "team", "name" => "team"}

    body = conn |> delete(~p"/api/workspaces/#{ws.slug}/views/pinme/pin") |> json_response(200)
    assert body["view"]["pinned"] == false
  end

  test "bucket lifecycle: create, list, visibility, members, move, delete", %{
    owner_conn: owner_conn,
    other_conn: other_conn,
    ws: ws,
    owner: owner,
    other: other
  } do
    body =
      owner_conn
      |> post(~p"/api/workspaces/#{ws.slug}/view-buckets", %{"name" => "launch"})
      |> json_response(200)

    assert body["bucket"] == %{
             "name" => "launch",
             "kind" => "project",
             "visibility" => "private",
             "owner" => owner.username,
             "members" => []
           }

    # Private project bucket is invisible to non-members.
    bucket_names = fn conn ->
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/view-buckets")
      |> json_response(200)
      |> Map.fetch!("buckets")
      |> Enum.map(& &1["name"])
    end

    refute "launch" in bucket_names.(other_conn)

    body =
      owner_conn
      |> post(~p"/api/workspaces/#{ws.slug}/view-buckets/launch/members", %{"username" => other.username})
      |> json_response(200)

    assert body == %{"ok" => true, "bucket" => "launch", "username" => other.username}
    assert "launch" in bucket_names.(other_conn)

    # Members can create views there; the owner sees them.
    other_conn
    |> create_view(ws, %{"name" => "launch-list", "description" => "Launch tasks.", "bucket" => "launch"})
    |> json_response(200)

    # Deleting a non-empty bucket fails.
    body = owner_conn |> delete(~p"/api/workspaces/#{ws.slug}/view-buckets/launch") |> json_response(422)
    assert body["error"]["message"] == "move or delete this bucket's views first"

    # Move the view out (view owner only), then delete the bucket.
    body =
      other_conn
      |> put(~p"/api/workspaces/#{ws.slug}/views/launch-list/bucket", %{"bucket" => "yours"})
      |> json_response(200)

    assert body["view"]["bucket"]["kind"] == "personal"

    # Removed members lose access.
    owner_conn
    |> delete(~p"/api/workspaces/#{ws.slug}/view-buckets/launch/members/#{other.username}")
    |> json_response(200)

    refute "launch" in bucket_names.(other_conn)

    # Visibility flips are owner-only and in place.
    body =
      other_conn
      |> put(~p"/api/workspaces/#{ws.slug}/view-buckets/launch/visibility", %{"visibility" => "workspace"})
      |> json_response(404)

    assert body["error"]["code"] == "not_found"

    body =
      owner_conn
      |> put(~p"/api/workspaces/#{ws.slug}/view-buckets/launch/visibility", %{"visibility" => "workspace"})
      |> json_response(200)

    assert body["bucket"]["visibility"] == "workspace"
    assert "launch" in bucket_names.(other_conn)

    assert owner_conn |> delete(~p"/api/workspaces/#{ws.slug}/view-buckets/launch") |> json_response(200)
    refute "launch" in bucket_names.(owner_conn)
  end

  test "bucket guardrails: reserved names, unknown members, foreign moves", %{
    owner_conn: owner_conn,
    other_conn: other_conn,
    ws: ws,
    other: other
  } do
    body =
      owner_conn
      |> post(~p"/api/workspaces/#{ws.slug}/view-buckets", %{"name" => "team"})
      |> json_response(422)

    assert body["error"]["message"] == "that bucket name is reserved"

    owner_conn
    |> post(~p"/api/workspaces/#{ws.slug}/view-buckets", %{"name" => "squad"})
    |> json_response(200)

    body =
      owner_conn
      |> post(~p"/api/workspaces/#{ws.slug}/view-buckets/squad/members", %{"username" => "nobody-here"})
      |> json_response(422)

    assert body["error"]["code"] == "not_member"

    # Only the view's owner can move it, even if both can use it.
    owner_conn
    |> create_view(ws, %{"name" => "shared", "description" => "For everyone here.", "bucket" => "team"})
    |> json_response(200)

    owner_conn
    |> post(~p"/api/workspaces/#{ws.slug}/view-buckets/squad/members", %{"username" => other.username})
    |> json_response(200)

    body =
      other_conn
      |> put(~p"/api/workspaces/#{ws.slug}/views/shared/bucket", %{"bucket" => "squad"})
      |> json_response(422)

    assert body["error"]["message"] == "only the view's owner can move it"

    body =
      owner_conn
      |> put(~p"/api/workspaces/#{ws.slug}/views/shared/bucket", %{"bucket" => "nope"})
      |> json_response(404)

    assert body["error"]["code"] == "not_found"
  end
end
