defmodule AvelineWeb.Api.FeWorkspaceControllerTest do
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  # /papi routes: session-cookie auth + CSRF. Tests sign in via the test
  # session and skip CSRF the same way other browser-pipeline tests do.
  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("accept", "application/json")

    {:ok, conn: conn, user: user, ws: ws}
  end

  describe "GET /papi/workspaces/:slug/home" do
    test "returns the home bundle", %{conn: conn, user: u, ws: ws} do
      doc_fixture(ws, u, title: "Runbook")

      body = conn |> get("/papi/workspaces/#{ws.slug}/home") |> json_response(200)

      assert body["ok"] == true
      assert body["viewer"]["username"] == u.username
      assert body["viewer"]["display_name"] == u.display_name
      assert is_list(body["pinned_docs"])
      assert is_list(body["needs_you"])
      assert is_list(body["recently_viewed"])
      assert Enum.any?(body["recent_changes"], &(&1["title"] == "Runbook"))
      # Fresh workspaces are seeded with an orientation doc.
      assert body["orientation"]["slug"]
    end

    test "401 when not signed in", %{ws: ws} do
      body =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("accept", "application/json")
        |> get("/papi/workspaces/#{ws.slug}/home")
        |> json_response(401)

      assert body["error"]["code"] == "unauthorized"
    end
  end

  describe "GET /papi/workspaces/:slug/welcome" do
    test "returns prompt, counts, and member names excluding self", %{conn: conn, ws: ws} do
      body = conn |> get("/papi/workspaces/#{ws.slug}/welcome") |> json_response(200)

      assert body["prompt"] =~ ws.slug
      assert is_integer(body["doc_count"])
      assert is_integer(body["view_count"])
      assert body["member_names"] == []
      assert is_list(body["backdrop_docs"])
    end
  end

  describe "GET /papi/workspaces/:slug/team" do
    test "returns totals, contributors, and no invite by default", %{conn: conn, user: u, ws: ws} do
      body = conn |> get("/papi/workspaces/#{ws.slug}/team") |> json_response(200)

      assert body["invite"] == nil
      assert is_integer(body["totals"]["active_docs"])
      assert Enum.any?(body["contributors"], &(&1["user_id"] == u.id))
    end
  end

  describe "POST /papi/workspaces/:slug/invite/rotate" do
    test "revokes the old link and mints a fresh one", %{conn: conn, user: u, ws: ws} do
      {:ok, old} = Aveline.Workspaces.ensure_invite(ws.id, u.id)

      body = conn |> post("/papi/workspaces/#{ws.slug}/invite/rotate") |> json_response(200)

      assert body["invite"]["code"]
      assert body["invite"]["code"] != old.code
      assert body["invite"]["url"] =~ "/invite/" <> body["invite"]["code"]
    end
  end

  describe "PUT /papi/workspaces/:slug/profile" do
    test "updates the display name", %{conn: conn, ws: ws} do
      body =
        conn
        |> put("/papi/workspaces/#{ws.slug}/profile", %{"display_name" => "  Alice  "})
        |> json_response(200)

      assert body["user"]["display_name"] == "Alice"
    end

    test "blank clears the display name", %{conn: conn, ws: ws} do
      body =
        conn
        |> put("/papi/workspaces/#{ws.slug}/profile", %{"display_name" => "   "})
        |> json_response(200)

      assert body["user"]["display_name"] == nil
    end
  end
end
