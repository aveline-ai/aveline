defmodule AvelineWeb.Api.DocPortedEndpointsTest do
  @moduledoc """
  Integration locks for the DocController/VersionController actions
  rewired onto the Gleam handlers that had no dedicated API coverage:
  orientation, restore, pin/unpin, versions, run-block, and the
  contract hint on block validation failures.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_t, plaintext} = token_fixture(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user, ws: ws}
  end

  test "get-orientation returns the seeded doc and records an agent view", %{
    conn: conn,
    ws: ws,
    user: user
  } do
    body = conn |> get(~p"/api/workspaces/#{ws.slug}/orientation") |> json_response(200)

    assert body["ok"] == true
    assert body["doc"]["orientation"] == true
    assert is_list(body["doc"]["blocks"])

    orientation = Aveline.Docs.get_orientation(ws.id)
    assert Aveline.DocViews.agent_viewed?(orientation.base_doc_id, user.id)
  end

  test "restore: 404 unknown slug, not_user_deleted when live, ok after delete", %{
    conn: conn,
    ws: ws,
    user: user
  } do
    doc = doc_fixture(ws, user, title: "Comeback")

    assert conn
           |> post(~p"/api/workspaces/#{ws.slug}/docs/nope/restore")
           |> json_response(404)

    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/restore")
      |> json_response(422)

    assert body["error"]["code"] == "not_user_deleted"

    assert conn |> delete(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}") |> json_response(200)

    restored =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/restore")
      |> json_response(200)

    assert restored["ok"] == true
    assert restored["slug"] == doc.slug
    assert restored["doc_id"] == doc.base_doc_id
    assert restored["version_number"] == doc.version_number

    assert conn
           |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}")
           |> json_response(200)
  end

  test "restore: a deleted private doc does not exist for non-owners", %{conn: conn, ws: ws} do
    owner = user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, owner.id)
    doc = doc_fixture(ws, owner, title: "Hidden", visibility: "private")
    {:ok, _} = Aveline.Docs.soft_delete(doc, owner.id)

    assert conn
           |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/restore")
           |> json_response(404)
  end

  test "pin lifecycle: lowest free slot, explicit slot, taken, unpin", %{
    conn: conn,
    ws: ws,
    user: user
  } do
    a = doc_fixture(ws, user, title: "Alpha")
    b = doc_fixture(ws, user, title: "Beta")

    pinned =
      conn |> post(~p"/api/workspaces/#{ws.slug}/docs/#{a.slug}/pin", %{}) |> json_response(200)

    assert pinned["slug"] == a.slug
    assert pinned["pin_slot"] == 1

    taken =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{b.slug}/pin", %{"slot" => 1})
      |> json_response(422)

    assert taken["error"]["code"] == "pin_slot_taken"
    assert taken["error"]["details"]["slot"] == 1
    assert taken["error"]["details"]["occupant"] == a.slug

    explicit =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{b.slug}/pin", %{"slot" => "4"})
      |> json_response(200)

    assert explicit["pin_slot"] == 4

    bad =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{b.slug}/pin", %{"slot" => 9})
      |> json_response(422)

    assert bad["error"]["message"] == "pin slot must be between 1 and 6"

    unpinned =
      conn |> delete(~p"/api/workspaces/#{ws.slug}/docs/#{b.slug}/pin") |> json_response(200)

    assert unpinned["pin_slot"] == nil

    not_pinned =
      conn |> delete(~p"/api/workspaces/#{ws.slug}/docs/#{b.slug}/pin") |> json_response(422)

    assert not_pinned["error"]["message"] == "doc is not pinned"
  end

  test "pin: private docs and the orientation doc can't be slotted", %{
    conn: conn,
    ws: ws,
    user: user
  } do
    private = doc_fixture(ws, user, title: "Quiet", visibility: "private")

    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{private.slug}/pin", %{})
      |> json_response(422)

    assert body["error"]["message"] =~ "private docs can't be pinned"

    orientation = Aveline.Docs.get_orientation(ws.id)

    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/#{orientation.slug}/pin", %{})
      |> json_response(422)

    assert body["error"]["message"] =~ "its own card"
  end

  test "versions: list + fetch one, unknown version 404", %{conn: conn, ws: ws, user: user} do
    doc = doc_fixture(ws, user, title: "History")

    {:ok, _v2} =
      Aveline.Docs.apply_ops(
        doc,
        [
          %{
            "op" => "append_block",
            "block" => %{"type" => "paragraph", "content" => [%{"text" => "More"}]}
          }
        ],
        %{actor_user_id: user.id, actor_type: "agent"},
        intent: "grow",
        resolves_comment_ids: []
      )

    list =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/versions")
      |> json_response(200)

    assert list["current_version"] == 2
    assert Enum.map(list["versions"], & &1["version_number"]) == [2, 1]

    v1 =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/versions/1")
      |> json_response(200)

    assert v1["doc"]["version_number"] == 1
    assert length(v1["doc"]["blocks"]) == 1

    assert conn
           |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/versions/99")
           |> json_response(404)

    assert conn
           |> get(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/versions/abc")
           |> json_response(404)
  end

  test "run-block 404s for unknown docs and non-chart blocks", %{conn: conn, ws: ws, user: user} do
    doc = doc_fixture(ws, user, title: "Plain")
    [block] = Aveline.Docs.get_current_by_slug(ws.id, doc.slug).blocks

    assert conn
           |> post(~p"/api/workspaces/#{ws.slug}/docs/nope/blocks/b1/run")
           |> json_response(404)

    assert conn
           |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/blocks/#{block["id"]}/run")
           |> json_response(404)
  end

  test "block validation failures carry the contract hint", %{conn: conn, ws: ws} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs", %{
        "title" => "Broken",
        "blocks" => [%{"type" => "mystery"}]
      })
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
    assert body["error"]["message"] =~ "Run `aveline contract`"
  end
end
