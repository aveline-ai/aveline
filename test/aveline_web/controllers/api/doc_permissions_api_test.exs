defmodule AvelineWeb.Api.DocPermissionsApiTest do
  @moduledoc """
  Doc permissions over the HTTP API: the coworker scenario. The owner
  makes a doc private; a second member must see 404 everywhere (show,
  edit, comments, listing, versions) with no title leak; shares reopen
  exactly what the role grants.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  setup %{conn: conn} do
    owner = user_fixture()
    other = user_fixture()
    ws = workspace_fixture(owner)
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)
    doc = doc_fixture(ws, owner, title: "Secret plan")

    {_t, owner_token} = token_fixture(owner)
    {_t, other_token} = token_fixture(other)

    as = fn token ->
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
    end

    {:ok,
     owner_conn: as.(owner_token),
     other_conn: as.(other_token),
     owner: owner,
     other: other,
     ws: ws,
     doc: doc}
  end

  test "private lifecycle: hide, 404 everywhere, share back, editor edits", ctx do
    %{owner_conn: owner_conn, other_conn: other_conn, other: other, ws: ws, doc: doc} = ctx

    # Owner flips the doc private.
    body =
      owner_conn
      |> put(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/visibility", %{
        "visibility" => "private"
      })
      |> json_response(200)

    assert body["visibility"] == "private"

    # Other member: gone from the list, 404 on every by-slug surface.
    list = other_conn |> get(~p"/api/workspaces/#{ws.slug}/docs") |> json_response(200)
    refute Enum.any?(list["docs"], &(&1["slug"] == doc.slug))

    assert other_conn |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}") |> json_response(404)

    assert other_conn
           |> patch(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}", %{
             "operations" => [],
             "intent" => "sneaky"
           })
           |> json_response(404)

    assert other_conn
           |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments")
           |> json_response(404)

    assert other_conn
           |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/versions/1")
           |> json_response(404)

    # Owner still reads it fine.
    assert owner_conn |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}") |> json_response(200)

    # Non-owner cannot flip visibility or share.
    assert other_conn
           |> put(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/visibility", %{
             "visibility" => "workspace"
           })
           |> json_response(404)

    # Viewer share: read + comment work, edit is 403.
    share_body =
      owner_conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/shares", %{
        "username" => other.username,
        "role" => "viewer"
      })
      |> json_response(200)

    assert share_body["role"] == "viewer"

    assert other_conn |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}") |> json_response(200)

    assert other_conn
           |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{
             "body" => "viewer can comment"
           })
           |> json_response(200)

    edit_resp =
      other_conn
      |> patch(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}", %{
        "operations" => [
          %{
            "op" => "append_block",
            "block" => %{"type" => "paragraph", "content" => [%{"text" => "nope"}]}
          }
        ],
        "intent" => "viewer tries to edit"
      })
      |> json_response(403)

    assert edit_resp["error"]["code"] == "forbidden"

    # Upgrade to editor: the same edit ships.
    owner_conn
    |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/shares", %{
      "username" => other.username,
      "role" => "editor"
    })
    |> json_response(200)

    assert other_conn
           |> patch(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}", %{
             "operations" => [
               %{
                 "op" => "append_block",
                 "block" => %{"type" => "paragraph", "content" => [%{"text" => "allowed"}]}
               }
             ],
             "intent" => "editor edits"
           })
           |> json_response(200)

    # Shares listing shows the live grant.
    shares = owner_conn |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/shares") |> json_response(200)
    assert [%{"username" => u, "role" => "editor"}] = shares["shares"]
    assert u == other.username

    # Revoke: the doc vanishes again.
    owner_conn
    |> delete(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/shares/#{other.username}")
    |> json_response(200)

    assert other_conn |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}") |> json_response(404)
  end

  test "create-doc accepts visibility: private is born hidden", ctx do
    %{owner_conn: owner_conn, other_conn: other_conn, ws: ws} = ctx

    created =
      owner_conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs", %{
        "title" => "Born secret",
        "visibility" => "private",
        "blocks" => [%{"type" => "paragraph", "content" => [%{"text" => "shh"}]}],
        "intent" => "test"
      })
      |> json_response(200)

    slug = created["slug"]

    assert owner_conn |> get(~p"/api/workspaces/#{ws.slug}/docs/#{slug}") |> json_response(200)
    assert other_conn |> get(~p"/api/workspaces/#{ws.slug}/docs/#{slug}") |> json_response(404)
  end

  test "events feed hides the private doc's trail", ctx do
    %{owner_conn: owner_conn, other_conn: other_conn, ws: ws, doc: doc} = ctx

    owner_conn
    |> put(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/visibility", %{"visibility" => "private"})
    |> json_response(200)

    other_events = other_conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)

    refute Enum.any?(other_events["events"], fn e -> e["target_slug"] == doc.slug end)
  end
end
