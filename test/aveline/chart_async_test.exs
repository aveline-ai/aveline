defmodule Aveline.ChartAsyncTest do
  @moduledoc """
  The context half of the async chart engine: enrichment that defers
  execution (`run_charts: false`), the LiveView's run entry point
  (`run_chart/2`), and the cache's single-flight + bust semantics.
  """
  use Aveline.DataCase, async: false

  alias Aveline.DataSources
  alias Aveline.DataSources.Cache
  alias Aveline.Docs
  alias Aveline.Fixtures

  # The test database itself — the runner opens a real second
  # connection, so queries must not depend on sandboxed rows.
  defp self_template do
    "postgres://#{System.get_env("PGUSER") || "postgres"}:<password>@#{System.get_env("PGHOST") || "localhost"}/aveline_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

  defp self_password, do: System.get_env("PGPASSWORD") || "postgres"

  setup do
    Cache.flush()
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    {:ok, ds} = DataSources.create(ws.id, "self", self_template(), self_password(), user.id)
    %{user: user, ws: ws, ds: ds}
  end

  describe "enrich_blocks run_charts: false" do
    test "live charts come back pending with the source echoed", %{ws: ws, user: user} do
      Fixtures.query_fixture(ws, user, "ones", "select 1 as one", source: "self")
      doc = Fixtures.doc_fixture(ws, user, blocks: [Fixtures.chart_block("ones")])

      assert [%{"result" => %{"pending" => true}, "source" => %{"name" => "self"}, "query_sql" => "select 1 as one"}] =
               Docs.enrich_blocks(doc.blocks, ws.id, run_charts: false)
    end

    test "a missing query resolves to an error immediately (nothing to run)", %{ws: ws, user: user} do
      Fixtures.query_fixture(ws, user, "gone", "select 1", source: "self")
      doc = Fixtures.doc_fixture(ws, user, blocks: [Fixtures.chart_block("gone")])
      # Delete the query out from under the chart.
      q = Aveline.DataSources.Queries.get_current_by_name(ws.id, "gone")
      {:ok, _} = Aveline.DataSources.Queries.delete(q, user.id)

      assert [%{"result" => %{"error" => "catalog query" <> _}}] =
               Docs.enrich_blocks(doc.blocks, ws.id, run_charts: false)
    end
  end

  describe "run_chart/2" do
    test "runs a raw-query chart through the cache and returns the result map", %{ws: ws, user: user} do
      Fixtures.query_fixture(ws, user, "one", "select 1 as one", source: "self")
      assert %{"columns" => ["one"], "rows" => [[1]]} = Docs.run_chart(ws.id, Fixtures.chart_block("one"))
    end

    test "bad SQL is an error state, not a raise", %{ws: ws, user: user} do
      Fixtures.query_fixture(ws, user, "boom", "select nope from nowhere", source: "self")
      assert %{"error" => msg} = Docs.run_chart(ws.id, Fixtures.chart_block("boom"))
      assert msg =~ "nowhere"
    end

    test "unknown query is an error state", %{ws: ws} do
      assert %{"error" => "catalog query" <> _} = Docs.run_chart(ws.id, Fixtures.chart_block("nonexistent"))
    end
  end

  describe "cache single-flight + bust" do
    # clock_timestamp() changes per call, so identical values prove the
    # concurrent misses coalesced into one dial.
    @stamp "select clock_timestamp()::text as t"

    test "concurrent identical misses coalesce into one run", %{ds: ds} do
      results =
        1..4
        |> Enum.map(fn _ -> Task.async(fn -> Cache.run(ds, @stamp) end) end)
        |> Task.await_many(30_000)

      stamps = Enum.map(results, fn {:ok, %{"rows" => [[t]]}} -> t end)
      assert length(Enum.uniq(stamps)) == 1
    end

    test "bust drops the entry so the next run re-dials", %{ds: ds} do
      {:ok, %{"rows" => [[t1]]}} = Cache.run(ds, @stamp)

      # Cached: same stamp.
      {:ok, %{"rows" => [[^t1]]}} = Cache.run(ds, @stamp)

      Cache.bust(ds.base_data_source_id, @stamp)
      {:ok, %{"rows" => [[t2]]}} = Cache.run(ds, @stamp)
      assert t2 != t1
    end
  end
end
