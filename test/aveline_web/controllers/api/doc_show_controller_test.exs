defmodule AvelineWeb.Api.DocShowControllerTest do
  @moduledoc """
  fe-doc-show reader endpoints (/papi only, session-cookie auth).
  Covers the GET surface the Elm doc-show page reads on mount.
  """
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  alias Aveline.Comments
  alias Aveline.Docs
  alias Aveline.Kudos

  setup %{conn: conn} do
    owner = user_fixture()
    other = user_fixture()
    ws = workspace_fixture(owner)
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)

    doc =
      doc_fixture(ws, owner,
        title: "Reader doc",
        blocks: [
          %{"type" => "heading", "level" => 2, "text" => "Intro"},
          %{"type" => "paragraph", "content" => [%{"text" => "Hello world"}]}
        ]
      )

    as = fn user ->
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put_req_header("accept", "application/json")
    end

    {:ok, owner_conn: as.(owner), other_conn: as.(other), ws: ws, doc: doc, owner: owner, other: other}
  end

  test "reader returns doc_full and records a human read", %{other_conn: conn, ws: ws, doc: doc} do
    body = conn |> get(~p"/papi/workspaces/#{ws.slug}/docs/#{doc.slug}/reader") |> json_response(200)

    assert body["doc"]["slug"] == doc.slug
    assert body["doc"]["title"] == "Reader doc"
    assert [%{"type" => "heading"}, %{"type" => "paragraph"}] = body["doc"]["blocks"]

    kudos = conn |> get(~p"/papi/workspaces/#{ws.slug}/docs/#{doc.slug}/kudos") |> json_response(200)
    assert kudos["view_count"] == 1
  end

  test "kudos state without toggling", %{other_conn: conn, ws: ws, doc: doc, other: other} do
    {:ok, _} = Kudos.toggle(ws.id, doc.base_doc_id, other.id)

    body = conn |> get(~p"/papi/workspaces/#{ws.slug}/docs/#{doc.slug}/kudos") |> json_response(200)
    assert body["given_by_me"] == true
    assert body["count"] == 1
    assert is_integer(body["view_count"])
  end

  test "history returns versions with dispositions and updated_at", %{owner_conn: conn, ws: ws, doc: doc, owner: owner} do
    {:ok, _v2} =
      Docs.replace_blocks(
        doc,
        [%{"type" => "paragraph", "content" => [%{"text" => "v2 body"}]}],
        %{actor_user_id: owner.id, actor_type: "human"},
        intent: "second pass"
      )

    body = conn |> get(~p"/papi/workspaces/#{ws.slug}/docs/#{doc.slug}/history") |> json_response(200)

    assert body["current_version"] == 2
    assert [v2, v1] = body["versions"]
    assert v2["version_number"] == 2
    assert v2["intent"] == "second pass"
    assert is_list(v2["comment_dispositions"])
    assert v1["version_number"] == 1
    assert v1["updated_at"]
  end

  test "version comments carry snippet + resolved_by_doc_id and honor include_deleted",
       %{owner_conn: conn, ws: ws, doc: doc, owner: owner} do
    [%{"id" => heading_id} | _] = doc.blocks

    {:ok, c1} =
      Comments.create_comment(%{
        "doc_id" => doc.id,
        "block_id" => heading_id,
        "body" => "anchored question",
        "actor_user_id" => owner.id,
        "actor_type" => "human"
      })

    {:ok, c2} =
      Comments.create_comment(%{
        "doc_id" => doc.id,
        "body" => "doomed comment",
        "actor_user_id" => owner.id,
        "actor_type" => "human"
      })

    {:ok, _} = Comments.soft_delete_comment(c2, owner.id)

    base = ~p"/papi/workspaces/#{ws.slug}/docs/#{doc.slug}/versions/1/comments"

    body = conn |> get(base) |> json_response(200)
    assert body["doc_version_id"] == doc.id
    assert [only] = body["comments"]
    assert only["id"] == c1.base_comment_id
    assert only["context_snippet"] == "Intro"
    assert Map.has_key?(only, "resolved_by_doc_id")

    body = conn |> get(base <> "?include_deleted=true") |> json_response(200)
    assert length(body["comments"]) == 2
  end

  test "unknown version is 404", %{owner_conn: conn, ws: ws, doc: doc} do
    assert conn
           |> get(~p"/papi/workspaces/#{ws.slug}/docs/#{doc.slug}/versions/99/comments")
           |> json_response(404)
  end

  test "private doc is invisible to a non-shared member", %{owner_conn: owner_conn, other_conn: other_conn, ws: ws, doc: doc, owner: owner} do
    {:ok, _} = Docs.set_visibility(doc, "private", owner.id)

    assert other_conn
           |> get(~p"/papi/workspaces/#{ws.slug}/docs/#{doc.slug}/kudos")
           |> json_response(404)

    assert owner_conn
           |> get(~p"/papi/workspaces/#{ws.slug}/docs/#{doc.slug}/kudos")
           |> json_response(200)
  end
end
