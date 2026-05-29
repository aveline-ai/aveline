defmodule AvelineWeb.Api.ViewControllerTest do
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_t, plaintext} = token_fixture(user)
    conn = conn |> put_req_header("authorization", "Bearer #{plaintext}")
    {:ok, conn: conn, user: user, ws: ws}
  end

  test "create + show + index + items", %{conn: conn, ws: ws} do
    _ = conn |> post(~p"/api/workspaces/#{ws.slug}/items", %{title: "a", tags: ["oncall"]})
    _ = conn |> post(~p"/api/workspaces/#{ws.slug}/items", %{title: "b", tags: ["other"]})

    payload = %{slug: "oncall", name: "Oncall", tag_filter: ["oncall"]}
    body = conn |> post(~p"/api/workspaces/#{ws.slug}/views", payload) |> json_response(201)
    assert body["slug"] == "oncall"

    show = conn |> get(~p"/api/workspaces/#{ws.slug}/views/oncall") |> json_response(200)
    assert show["view"]["slug"] == "oncall"
    assert length(show["items"]) == 1
    assert hd(show["items"])["title"] == "a"

    idx = conn |> get(~p"/api/workspaces/#{ws.slug}/views") |> json_response(200)
    assert length(idx["views"]) == 1
  end

  test "tag_invalid for bad tag_filter", %{conn: conn, ws: ws} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/views", %{slug: "bad", name: "bad", tag_filter: ["BAD"]})
      |> json_response(422)

    assert body["error"]["code"] == "tag_invalid"
    assert body["error"]["field"] == "tag_filter"
  end

  test "soft delete excludes from list", %{conn: conn, ws: ws} do
    _ = conn |> post(~p"/api/workspaces/#{ws.slug}/views", %{slug: "v1", name: "v1"})
    _ = conn |> delete(~p"/api/workspaces/#{ws.slug}/views/v1") |> json_response(200)
    idx = conn |> get(~p"/api/workspaces/#{ws.slug}/views") |> json_response(200)
    assert idx["views"] == []
  end

  test "404 on missing view", %{conn: conn, ws: ws} do
    body = conn |> get(~p"/api/workspaces/#{ws.slug}/views/nope") |> json_response(404)
    assert body["error"]["code"] == "not_found"
  end
end
