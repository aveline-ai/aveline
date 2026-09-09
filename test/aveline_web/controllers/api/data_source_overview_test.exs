defmodule AvelineWeb.Api.DataSourceOverviewTest do
  @moduledoc """
  GET /papi/workspaces/:slug/data-sources-overview — the one-roundtrip
  bootstrap the Elm Data sources page consumes. Asserts it mirrors what
  DataSourcesLive.mount/3 assembled: every current source incl.
  soft-deleted, the catalog with chart usage and derived lineage, and
  active milestones.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  alias Aveline.DataSources
  alias Aveline.DataSources.Queries

  defp self_template do
    "postgres://#{System.get_env("PGUSER") || "postgres"}:<password>@#{System.get_env("PGHOST") || "localhost"}/aveline_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

  defp self_password, do: System.get_env("PGPASSWORD") || "postgres"

  setup %{conn: conn} do
    Aveline.DataSources.Cache.flush()
    user = user_fixture()
    ws = workspace_fixture(user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)
      |> Plug.Conn.put_req_header("accept", "application/json")

    {:ok, conn: conn, user: user, ws: ws}
  end

  test "returns sources (incl. deleted), catalog usage + lineage, and milestones",
       %{conn: conn, user: user, ws: ws} do
    {:ok, _} = DataSources.create(ws.id, "self", self_template(), self_password(), user.id)
    {:ok, gone} = DataSources.create(ws.id, "gone", self_template(), self_password(), user.id)
    {:ok, _} = DataSources.delete(gone, user.id)

    {:ok, _} =
      Queries.create(ws.id, %{name: "signups", sql: "select 1 as n", source: "self"}, user.id)

    {:ok, _} =
      Queries.create(ws.id, %{name: "doubled", sql: "select n * 2 as n2 from signups"}, user.id)

    doc_fixture(ws, user, %{
      blocks: [%{"type" => "chart", "query_ref" => "signups", "spec" => %{}}]
    })

    {:ok, _} =
      Aveline.Milestones.create(ws.id, %{name: "v1 shipped", date: ~D[2026-07-06]}, user.id)

    body =
      conn
      |> get("/papi/workspaces/#{ws.slug}/data-sources-overview")
      |> json_response(200)

    assert body["ok"] == true

    by_name = Map.new(body["sources"], &{&1["name"], &1})
    assert by_name["self"]["deleted"] == false
    assert by_name["self"]["created_by"] == user.username
    assert by_name["self"]["adapter"] == "postgres"
    assert by_name["self"]["url"] =~ "<password>"
    assert by_name["gone"]["deleted"] == true
    assert is_binary(by_name["self"]["base_id"])

    queries = Map.new(body["queries"], &{&1["name"], &1})
    assert queries["signups"]["kind"] == "raw"
    assert queries["signups"]["data_source_id"] == by_name["self"]["base_id"]
    assert queries["signups"]["chart_count"] == 1
    assert [%{"slug" => _, "title" => _}] = queries["signups"]["charted_in"]
    assert queries["signups"]["created_by"] == user.username

    assert queries["doubled"]["kind"] == "derived"
    assert queries["doubled"]["data_source_id"] == nil
    assert queries["doubled"]["built_on"] == ["signups"]
    assert queries["doubled"]["chart_count"] == 0

    assert [%{"name" => "v1 shipped", "date" => "2026-07-06"}] = body["milestones"]
  end

  test "401 without a session", %{ws: ws} do
    body =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{})
      |> get("/papi/workspaces/#{ws.slug}/data-sources-overview")
      |> json_response(401)

    assert body["ok"] == false
  end

  test "403 for a non-member", %{ws: ws} do
    other = user_fixture()

    body =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> get("/papi/workspaces/#{ws.slug}/data-sources-overview")
      |> json_response(403)

    assert body["ok"] == false
  end
end
