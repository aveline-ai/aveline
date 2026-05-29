defmodule AvelineWeb.Api.MeControllerTest do
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_token, plaintext} = token_fixture(user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{plaintext}")

    {:ok, conn: conn, user: user, ws: ws, plaintext: plaintext}
  end

  test "GET /api/me returns user and workspaces", %{conn: conn, user: u, ws: ws} do
    body = conn |> get(~p"/api/me") |> json_response(200)

    assert body["user"]["id"] == u.id
    assert body["user"]["email"] == u.email
    assert body["user"]["username"] == u.username
    assert body["user"]["display_name"] == u.display_name
    assert [w] = body["workspaces"]
    assert w["slug"] == ws.slug
  end

  test "401 without token", %{} do
    body =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/me")
      |> json_response(401)

    assert body["error"]["code"] == "unauthorized"
  end

  test "401 with bad token", %{} do
    body =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer avl_bogus")
      |> get(~p"/api/me")
      |> json_response(401)

    assert body["error"]["code"] == "unauthorized"
  end
end
