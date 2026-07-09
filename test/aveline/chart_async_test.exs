defmodule Aveline.ChartAsyncTest do
  @moduledoc """
  The context half of the async chart engine: enrichment that defers
  execution (`run_charts: false`), the LiveView's run entry point
  (`run_chart_query/3`), and the cache's single-flight + bust semantics.
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
      doc =
        Fixtures.doc_fixture(ws, user, blocks: [%{"type" => "chart", "source" => "self", "query" => "select 1 as one"}])

      assert [%{"result" => %{"pending" => true}, "source" => %{"name" => "self"}}] =
               Docs.enrich_blocks(doc.blocks, ws.id, run_charts: false)
    end

    test "deleted sources still resolve to errors immediately (nothing to run)", %{
      ws: ws,
      user: user
    } do
      {:ok, doomed} =
        DataSources.create(ws.id, "doomed", self_template(), self_password(), user.id)

      doc =
        Fixtures.doc_fixture(ws, user, blocks: [%{"type" => "chart", "source" => "doomed", "query" => "select 1"}])

      {:ok, _} = DataSources.delete(doomed, user.id)

      assert [%{"result" => %{"error" => "data source was deleted" <> _}}] =
               Docs.enrich_blocks(doc.blocks, ws.id, run_charts: false)
    end
  end

  describe "run_chart_query/3" do
    test "runs through the cache and returns the result map", %{ws: ws, ds: ds} do
      assert %{"columns" => ["one"], "rows" => [[1]]} =
               Docs.run_chart_query(ws.id, ds.base_data_source_id, "select 1 as one")
    end

    test "bad SQL is an error state, not a raise", %{ws: ws, ds: ds} do
      assert %{"error" => msg} =
               Docs.run_chart_query(ws.id, ds.base_data_source_id, "select nope from nowhere")

      assert msg =~ "nowhere"
    end

    test "unknown source is an error state", %{ws: ws} do
      assert %{"error" => "data source not found"} =
               Docs.run_chart_query(ws.id, Ecto.UUID.generate(), "select 1")
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
