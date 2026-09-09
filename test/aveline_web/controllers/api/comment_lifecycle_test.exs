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

  test "create on unknown doc is 404", %{conn: conn, ws: ws} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/nope/comments", %{"body" => "hi"})
      |> json_response(404)

    assert body["error"]["code"] == "not_found"
  end

  test "missing or empty body fails validation", %{conn: conn, ws: ws, doc: doc} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{})
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"

    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{"body" => ""})
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
  end

  test "unknown actor fails validation", %{conn: conn, ws: ws, doc: doc} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{
        "body" => "hi",
        "actor" => "robot"
      })
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
  end

  test "unknown comment id is 404 on every mutation", %{conn: conn, ws: ws} do
    missing = Ecto.UUID.generate()

    for req <- [
          patch(conn, ~p"/api/workspaces/#{ws.slug}/comments/#{missing}", %{"body" => "x"}),
          delete(conn, ~p"/api/workspaces/#{ws.slug}/comments/#{missing}"),
          post(conn, ~p"/api/workspaces/#{ws.slug}/comments/#{missing}/undelete"),
          post(conn, ~p"/api/workspaces/#{ws.slug}/comments/#{missing}/resolve"),
          post(conn, ~p"/api/workspaces/#{ws.slug}/comments/#{missing}/unresolve")
        ] do
      assert json_response(req, 404)["error"]["code"] == "not_found"
    end
  end

  test "reply inherits the parent's block anchor", %{conn: conn, ws: ws, doc: doc} do
    block_id = hd(doc.blocks)["id"]

    parent =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{
        "body" => "anchored",
        "block_id" => block_id
      })
      |> json_response(200)

    reply =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{
        "body" => "reply",
        "parent_comment_id" => parent["id"]
      })
      |> json_response(200)

    list =
      conn |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments") |> json_response(200)

    reply_view = Enum.find(list["comments"], &(&1["id"] == reply["id"]))
    assert reply_view["block_id"] == block_id
    assert reply_view["parent_comment_id"] == parent["id"]
  end

  test "resolve is not author-gated; delete and undelete are", %{conn: conn, ws: ws, doc: doc} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{"body" => "mine"})
      |> json_response(200)

    id = body["id"]

    other = user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)
    {_t, other_token} = token_fixture(other)

    other_conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    # Anyone in the workspace can resolve / unresolve.
    assert other_conn
           |> post(~p"/api/workspaces/#{ws.slug}/comments/#{id}/resolve")
           |> json_response(200)

    assert other_conn
           |> post(~p"/api/workspaces/#{ws.slug}/comments/#{id}/unresolve")
           |> json_response(200)

    # Delete is author-only.
    del_body = other_conn |> delete(~p"/api/workspaces/#{ws.slug}/comments/#{id}") |> json_response(403)
    assert del_body["error"]["code"] == "forbidden"

    # Undelete is author-only too.
    assert conn |> delete(~p"/api/workspaces/#{ws.slug}/comments/#{id}") |> json_response(200)

    und_body = other_conn |> post(~p"/api/workspaces/#{ws.slug}/comments/#{id}/undelete") |> json_response(403)
    assert und_body["error"]["code"] == "forbidden"
  end

  test "comments on a private doc are invisible to non-shared members", %{
    conn: conn,
    ws: ws,
    doc: doc
  } do
    conn
    |> put(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/visibility", %{
      "visibility" => "private"
    })
    |> json_response(200)

    other = user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)
    {_t, other_token} = token_fixture(other)

    other_conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    assert other_conn
           |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments")
           |> json_response(404)

    assert other_conn
           |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{"body" => "hi"})
           |> json_response(404)
  end

  test "lifecycle records activity events with doc_base_id data", %{
    conn: conn,
    user: user,
    ws: ws,
    doc: doc
  } do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/comments", %{"body" => "hello"})
      |> json_response(200)

    id = body["id"]

    conn |> post(~p"/api/workspaces/#{ws.slug}/comments/#{id}/resolve") |> json_response(200)
    conn |> post(~p"/api/workspaces/#{ws.slug}/comments/#{id}/unresolve") |> json_response(200)
    conn |> patch(~p"/api/workspaces/#{ws.slug}/comments/#{id}", %{"body" => "v2"}) |> json_response(200)
    conn |> delete(~p"/api/workspaces/#{ws.slug}/comments/#{id}") |> json_response(200)

    events = Aveline.Events.list_for_workspace(ws.id)
    by_action = fn action -> Enum.find(events, &(&1.action == action and &1.target_id == id)) end

    created = by_action.("comment_created")
    assert created.actor_user_id == user.id
    assert created.actor_type == "agent"
    assert created.target_kind == "comment"
    assert created.target_slug == doc.slug
    assert created.data["doc_base_id"] == doc.base_doc_id

    resolved = by_action.("comment_resolved")
    assert resolved.actor_user_id == user.id
    assert resolved.actor_type == "human"
    assert Map.has_key?(resolved.data, "resolved_by_doc_id")

    assert by_action.("comment_unresolved")

    edited = by_action.("comment_edited")
    assert edited.data["version_number"] == 2

    deleted = by_action.("comment_deleted")
    assert deleted.actor_type == "human"
    assert deleted.actor_user_id == user.id
  end
end
