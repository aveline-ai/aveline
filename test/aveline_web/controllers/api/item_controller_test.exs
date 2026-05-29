defmodule AvelineWeb.Api.ItemControllerTest do
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_t, plaintext} = token_fixture(user)
    conn = conn |> put_req_header("authorization", "Bearer #{plaintext}")
    {:ok, conn: conn, user: user, ws: ws}
  end

  test "create + show + index", %{conn: conn, ws: ws} do
    payload = %{title: "Oncall Rotation", tags: ["oncall"], pinned: true}
    body = conn |> post(~p"/api/workspaces/#{ws.slug}/items", payload) |> json_response(201)
    assert body["item"]["slug"] == "oncall-rotation"
    assert body["item"]["pinned"] == true
    assert body["item"]["tags"] == ["oncall"]
    assert body["item"]["owner"]["username"]
    assert body["item"]["created_via"] == "cli"

    show = conn |> get(~p"/api/workspaces/#{ws.slug}/items/oncall-rotation") |> json_response(200)
    assert show["item"]["title"] == "Oncall Rotation"

    idx = conn |> get(~p"/api/workspaces/#{ws.slug}/items?pinned=true&tag=oncall") |> json_response(200)
    assert length(idx["items"]) == 1
  end

  test "validation_failed for empty title", %{conn: conn, ws: ws} do
    body = conn |> post(~p"/api/workspaces/#{ws.slug}/items", %{title: ""}) |> json_response(422)
    assert body["error"]["code"] == "validation_failed"
  end

  test "tag_invalid for bad tag", %{conn: conn, ws: ws} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/items", %{title: "x", tags: ["BAD TAG"]})
      |> json_response(422)

    assert body["error"]["code"] == "tag_invalid"
    assert body["error"]["field"] == "tags"
  end

  test "slug_taken on duplicate", %{conn: conn, ws: ws} do
    _ = conn |> post(~p"/api/workspaces/#{ws.slug}/items", %{title: "x", slug: "x"})
    body = conn |> post(~p"/api/workspaces/#{ws.slug}/items", %{title: "x", slug: "x"}) |> json_response(422)
    assert body["error"]["code"] == "slug_taken"
  end

  test "delete + list excludes + restore re-includes", %{conn: conn, ws: ws} do
    _ = conn |> post(~p"/api/workspaces/#{ws.slug}/items", %{title: "del", slug: "del"})
    _ = conn |> delete(~p"/api/workspaces/#{ws.slug}/items/del") |> json_response(200)
    idx = conn |> get(~p"/api/workspaces/#{ws.slug}/items") |> json_response(200)
    assert idx["items"] == []

    _ = conn |> post(~p"/api/workspaces/#{ws.slug}/items/del/restore") |> json_response(200)
    idx2 = conn |> get(~p"/api/workspaces/#{ws.slug}/items") |> json_response(200)
    assert length(idx2["items"]) == 1
  end

  test "update via PATCH", %{conn: conn, ws: ws} do
    _ = conn |> post(~p"/api/workspaces/#{ws.slug}/items", %{title: "u", slug: "u"})
    body = conn |> patch(~p"/api/workspaces/#{ws.slug}/items/u", %{title: "renamed"}) |> json_response(200)
    assert body["item"]["title"] == "renamed"
  end

  test "404 on missing item", %{conn: conn, ws: ws} do
    body = conn |> get(~p"/api/workspaces/#{ws.slug}/items/missing") |> json_response(404)
    assert body["error"]["code"] == "not_found"
  end

  test "403 when not member", %{conn: conn} do
    other = user_fixture()
    other_ws = workspace_fixture(other)
    body = conn |> get(~p"/api/workspaces/#{other_ws.slug}/items") |> json_response(403)
    assert body["error"]["code"] == "forbidden"
  end

  test "401 without token", %{ws: ws} do
    body =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/workspaces/#{ws.slug}/items")
      |> json_response(401)

    assert body["error"]["code"] == "unauthorized"
  end
end
