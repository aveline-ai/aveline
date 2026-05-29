defmodule AvelineWeb.Api.WorkspaceControllerTest do
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_t, plaintext} = token_fixture(user)
    conn = conn |> put_req_header("authorization", "Bearer #{plaintext}")
    {:ok, conn: conn, user: user, ws: ws}
  end

  test "index lists my workspaces", %{conn: conn, ws: ws} do
    body = conn |> get(~p"/api/workspaces") |> json_response(200)
    assert [w] = body["workspaces"]
    assert w["slug"] == ws.slug
  end

  test "show returns workspace", %{conn: conn, ws: ws} do
    body = conn |> get(~p"/api/workspaces/#{ws.slug}") |> json_response(200)
    assert body["slug"] == ws.slug
  end

  test "show 404 when missing", %{conn: conn} do
    body = conn |> get(~p"/api/workspaces/nope") |> json_response(404)
    assert body["error"]["code"] == "workspace_not_found"
  end

  test "show 403 when not a member", %{conn: conn} do
    other = user_fixture()
    other_ws = workspace_fixture(other)
    body = conn |> get(~p"/api/workspaces/#{other_ws.slug}") |> json_response(403)
    assert body["error"]["code"] == "forbidden"
  end
end
