defmodule AvelineWeb.Api.QueryCatalogApiTest do
  @moduledoc """
  The query-catalog API surface end to end: query CRUD, the per-source
  lineage listing, ad-hoc composition through the workspace source, and
  the reads-return-config-plus run-block contract change.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  alias Aveline.DataSources
  alias Aveline.DataSources.Engine

  defp self_template do
    "postgres://#{System.get_env("PGUSER") || "postgres"}:<password>@#{System.get_env("PGHOST") || "localhost"}/aveline_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

  defp self_password, do: System.get_env("PGPASSWORD") || "postgres"

  setup %{conn: conn} do
    Aveline.DataSources.Cache.flush()
    user = user_fixture()
    ws = workspace_fixture(user)
    {:ok, _src} = DataSources.create(ws.id, "self", self_template(), self_password(), user.id)
    {_t, plaintext} = token_fixture(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user, ws: ws}
  end

  test "query CRUD, lineage listing, and dependent protection", %{conn: conn, ws: ws} do
    base = ~p"/api/workspaces/#{ws.slug}/queries"

    # raw query
    body =
      conn
      |> post(base, %{
        "name" => "signups",
        "source" => "self",
        "sql" => "select 1 as n",
        "description" => "Daily signup count."
      })
      |> json_response(200)

    assert body["query"]["name"] == "signups"
    assert body["query"]["kind"] == "raw"
    assert body["query"]["description"] == "Daily signup count."

    # description edits are versioned and survive unrelated edits
    edited =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/queries/signups", %{"description" => "Signups per day."})
      |> json_response(200)

    assert edited["query"]["description"] == "Signups per day."
    assert edited["query"]["version_number"] == 2

    resqled =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/queries/signups", %{"sql" => "select 2 as n"})
      |> json_response(200)

    assert resqled["query"]["description"] == "Signups per day."

    # derived query on top
    conn
    |> post(base, %{"name" => "doubled", "sql" => "select n * 2 AS n2 FROM signups"})
    |> json_response(200)

    # lineage: queries built on the self source (the derived one is not)
    src = DataSources.get_current_by_name(ws.id, "self")

    listed =
      conn
      |> get(base, %{"source" => "self"})
      |> json_response(200)

    names = Enum.map(listed["queries"], & &1["name"])
    assert "signups" in names
    refute "doubled" in names
    assert src

    # the dependent blocks deleting the leaf
    del = conn |> delete(~p"/api/workspaces/#{ws.slug}/queries/signups") |> json_response(422)
    assert del["error"]["code"] == "query_has_dependents"

    # unknown reference is a clean validation error
    bad =
      conn
      |> post(base, %{"name" => "bad", "sql" => "select * FROM ghost"})
      |> json_response(422)

    assert bad["error"]["code"] == "invalid_query"
  end

  test "reserved and cyclic writes are rejected", %{conn: conn, ws: ws} do
    base = ~p"/api/workspaces/#{ws.slug}/queries"

    conn |> post(base, %{"name" => "a", "sql" => "select 1 as x"}) |> json_response(200)
    conn |> post(base, %{"name" => "b", "sql" => "select x FROM a"}) |> json_response(200)

    # a -> b would close a cycle with b -> a
    cyc =
      conn
      |> put(~p"/api/workspaces/#{ws.slug}/queries/a", %{"sql" => "select x FROM b"})
      |> json_response(422)

    assert cyc["error"]["code"] == "invalid_query"
  end

  @tag if Engine.available?(), do: [], else: [skip: "duckdb not fetched"]
  test "ad-hoc composition through the workspace source joins two queries", %{conn: conn, ws: ws} do
    base = ~p"/api/workspaces/#{ws.slug}/queries"

    conn
    |> post(base, %{"name" => "s", "source" => "self", "sql" => "select 1 as wk, 10 as n"})
    |> json_response(200)

    conn
    |> post(base, %{"name" => "d", "source" => "self", "sql" => "select 1 as wk, 100 as amt"})
    |> json_response(200)

    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/data-sources/derived/query", %{
        "query" => "select s.wk, d.amt::double / s.n AS cac FROM s JOIN d USING (wk)"
      })
      |> json_response(200)

    assert body["columns"] == ["wk", "cac"]
    assert [[1, 10.0]] = body["rows"]
  end

  test "reads return chart config only; run-block returns rows", %{conn: conn, ws: ws, user: user} do
    Aveline.DataSources.Queries.create(ws.id, %{name: "answer_q", source: "self", sql: "select 42 as answer"}, user.id)

    doc = doc_fixture(ws, user, slug: "metrics", blocks: [Aveline.Fixtures.chart_block("answer_q")])

    block_id = doc.blocks |> List.first() |> Map.fetch!("id")

    # get-doc: config echoed, query NOT run (pending), no rows.
    get_body =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/docs/metrics")
      |> json_response(200)

    chart = get_body["doc"]["blocks"] |> List.first()
    assert chart["result"] == %{"pending" => true}
    assert chart["source"]["name"] == "self"

    # run-block: explicit path to rows.
    run_body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs/metrics/blocks/#{block_id}/run")
      |> json_response(200)

    assert run_body["columns"] == ["answer"]
    assert run_body["rows"] == [[42]]
  end
end
