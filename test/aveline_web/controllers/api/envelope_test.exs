defmodule AvelineWeb.Api.EnvelopeTest do
  @moduledoc """
  Smoke-tests the canonical envelope shape across every API endpoint:
  successes are `{ok: true, ...}`, failures are
  `{ok: false, error: {code, message}}`. Hits every controller at least
  once so a refactor that breaks the envelope contract for one endpoint
  fails CI here.
  """
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_t, plaintext} = token_fixture(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext}")
      |> put_req_header("accept", "application/json")

    {:ok, conn: conn, user: user, ws: ws}
  end

  describe "envelope on success" do
    test "GET /api/heartbeat", %{conn: conn} do
      body = conn |> get(~p"/api/heartbeat") |> json_response(200)
      assert body["ok"] == true
      assert body["service"] == "aveline"
    end

    test "GET /api/me", %{conn: conn} do
      body = conn |> get(~p"/api/me") |> json_response(200)
      assert body["ok"] == true
      assert is_map(body["user"])
      assert is_list(body["workspaces"])
    end

    test "GET /api/workspaces", %{conn: conn} do
      body = conn |> get(~p"/api/workspaces") |> json_response(200)
      assert body["ok"] == true
      assert is_list(body["workspaces"])
    end

    test "GET /api/workspaces/:slug/docs", %{conn: conn, ws: ws} do
      body = conn |> get(~p"/api/workspaces/#{ws.slug}/docs") |> json_response(200)
      assert body["ok"] == true
      assert is_list(body["docs"])
    end

    test "GET /api/workspaces/:slug/tags", %{conn: conn, ws: ws} do
      body = conn |> get(~p"/api/workspaces/#{ws.slug}/tags") |> json_response(200)
      assert body["ok"] == true
      assert is_list(body["tags"])
    end

    test "GET /api/workspaces/:slug/members", %{conn: conn, ws: ws} do
      body = conn |> get(~p"/api/workspaces/#{ws.slug}/members") |> json_response(200)
      assert body["ok"] == true
      assert is_list(body["members"])
    end

    test "GET /api/workspaces/:slug/events", %{conn: conn, ws: ws} do
      body = conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)
      assert body["ok"] == true
      assert is_list(body["events"])
    end
  end

  describe "envelope on failure" do
    test "401 missing auth has error code", %{conn: _conn} do
      body =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/me")
        |> json_response(401)

      assert body["ok"] == false
      assert body["error"]["code"] == "unauthorized"
      assert is_binary(body["error"]["message"])
    end

    test "403 not a workspace member has error code", %{conn: conn} do
      other = user_fixture()
      other_ws = workspace_fixture(other)

      body =
        conn
        |> get(~p"/api/workspaces/#{other_ws.slug}/docs")
        |> json_response(403)

      assert body["ok"] == false
      assert body["error"]["code"] == "forbidden"
    end

    test "404 workspace not found", %{conn: conn} do
      body = conn |> get(~p"/api/workspaces/nope/docs") |> json_response(404)
      assert body["ok"] == false
      assert body["error"]["code"] == "workspace_not_found"
    end

    test "404 doc not found", %{conn: conn, ws: ws} do
      body = conn |> get(~p"/api/workspaces/#{ws.slug}/docs/nope") |> json_response(404)
      assert body["ok"] == false
      assert body["error"]["code"] == "not_found"
    end
  end
end
