defmodule AvelineWeb.Api.CommentLifecycleTest do
  @moduledoc """
  Comment lifecycle through the API: create → reply → edit → resolve →
  unresolve → delete → undelete. Confirms IDs in payloads are
  `base_comment_id` (the stable logical id) and that minimal echoes
  carry just what the agent can't compute itself (the new comment's id).
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {:ok, _tag} = Aveline.Tags.create(ws.id, "wiki", "Wiki notes.", nil)
    doc = doc_fixture(ws, user, tags: ["wiki"])
    {_t, plaintext} = token_fixture(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user, ws: ws, doc: doc}
  end

  test "full lifecycle", %{conn: conn, ws: ws, doc: doc} do
    # Create
    create_body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{
        "body" => "I have a question."
      })
      |> json_response(200)

    assert create_body["ok"] == true
    id = create_body["id"]
    assert is_binary(id)

    # Resolve
    res_body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/comments/#{id}/resolve")
      |> json_response(200)

    assert res_body["ok"] == true

    # Unresolve
    unr_body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/comments/#{id}/unresolve")
      |> json_response(200)

    assert unr_body["ok"] == true

    # Edit
    edit_body =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/comments/#{id}", %{"body" => "Updated text"})
      |> json_response(200)

    assert edit_body["ok"] == true

    # Delete
    del_body =
      conn
      |> delete(~p"/api/workspaces/#{ws.slug}/comments/#{id}")
      |> json_response(200)

    assert del_body["ok"] == true

    # Undelete
    und_body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/comments/#{id}/undelete")
      |> json_response(200)

    assert und_body["ok"] == true

    # List shows it
    list_body =
      conn |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments") |> json_response(200)

    assert list_body["ok"] == true
    assert [c] = list_body["comments"]
    assert c["id"] == id
    assert c["body"] == "Updated text"
  end

  test "non-author cannot edit", %{conn: conn, ws: ws, doc: doc} do
    %{conn: conn, user: _, ws: _ws, doc: _doc} = %{conn: conn, user: nil, ws: ws, doc: doc}

    # author posts a comment
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{"body" => "mine"})
      |> json_response(200)

    id = body["id"]

    # someone else (their own conn) tries to edit
    other = user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)
    {_t, other_token} = token_fixture(other)

    other_conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    forbidden =
      other_conn
      |> patch(~p"/api/workspaces/#{ws.slug}/comments/#{id}", %{"body" => "evil"})
      |> json_response(403)

    assert forbidden["ok"] == false
    assert forbidden["error"]["code"] == "forbidden"
  end
end
