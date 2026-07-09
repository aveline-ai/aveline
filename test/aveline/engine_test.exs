defmodule Aveline.DataSources.EngineTest do
  @moduledoc """
  The sandboxed analytics engine, exercised against the real vendored
  binary — these are the TIP's spike gates as regression tests: parse
  extraction (CTEs subtracted, non-SELECT rejected), hostile SQL dying
  against the hardening flags, typed round-trips (ASOF JOIN on
  timestamps), output caps, and kill-at-timeout.
  """
  use ExUnit.Case, async: true

  alias Aveline.DataSources.Engine

  if not Engine.available?() do
    @moduletag skip: "duckdb binary not fetched (mix duckdb.fetch)"
  end

  describe "parse/1" do
    test "extracts referenced tables, minus the statement's own CTEs" do
      sql = "WITH sm AS (SELECT * FROM signups) SELECT * FROM sm JOIN spend USING (week)"
      assert {:ok, ["signups", "spend"]} = Engine.parse(sql)
    end

    test "rejects non-SELECT statements" do
      assert {:error, msg} = Engine.parse("DROP TABLE users")
      assert msg =~ "SELECT"
    end

    test "rejects multiple statements" do
      assert {:error, msg} = Engine.parse("SELECT 1; SELECT 2")
      assert msg =~ "one SELECT"
    end

    test "rejects syntax errors with the engine's message" do
      assert {:error, msg} = Engine.parse("SELEKT everything")
      assert msg =~ "invalid analytics SQL"
    end
  end

  describe "run/3 composition" do
    test "typed leaves + derived chain + final SELECT" do
      leaves = [
        {"signups",
         %{
           "columns" => ["week", "n"],
           "rows" => [["2026-01-05 00:00:00", 10], ["2026-01-12 00:00:00", 14]]
         }}
      ]

      derived = [{"doubled", "SELECT week, n * 2 AS n2 FROM signups"}]

      assert {:ok, %{"columns" => ["week", "n2"], "rows" => rows, "truncated" => false}} =
               Engine.run(leaves, derived, "SELECT week, n2 FROM doubled ORDER BY week")

      assert [[_, 20], [_, 28]] = rows
    end

    test "timestamps sniff to real types: ASOF JOIN works" do
      leaves = [
        {"a", %{"columns" => ["t", "v"], "rows" => [["2026-01-01 00:00:00", 1], ["2026-01-03 00:00:00", 3]]}},
        {"b", %{"columns" => ["t", "w"], "rows" => [["2026-01-02 12:00:00", 20]]}}
      ]

      assert {:ok, %{"rows" => [[_, 1, 20]]}} =
               Engine.run(leaves, [], "SELECT b.t, a.v, b.w FROM b ASOF JOIN a ON b.t >= a.t")
    end

    test "regressions exist regardless of the source's dialect" do
      leaves = [
        {"pts", %{"columns" => ["x", "y"], "rows" => [[1.0, 2.0], [2.0, 4.0], [3.0, 6.0]]}}
      ]

      assert {:ok, %{"rows" => [[m]]}} = Engine.run(leaves, [], "SELECT regr_slope(y, x) AS m FROM pts")
      assert_in_delta m, 2.0, 0.0001
    end

    test "empty results keep their columns" do
      leaves = [{"e", %{"columns" => ["a", "b"], "rows" => []}}]

      assert {:ok, %{"columns" => ["a", "b"], "rows" => []}} =
               Engine.run(leaves, [], "SELECT * FROM e")
    end

    test "output caps at the row cap with a truncated flag" do
      assert {:ok, %{"rows" => rows, "truncated" => true}} =
               Engine.run([], [], "SELECT * FROM range(5000)")

      assert length(rows) == Aveline.DataSources.Runner.row_cap()
    end

    test "schema errors come back as engine messages, not raises" do
      leaves = [{"t", %{"columns" => ["a"], "rows" => [[1]]}}]
      assert {:error, msg} = Engine.run(leaves, [], "SELECT nope FROM t")
      assert msg =~ "nope"
    end

    test "values with quotes and NULLs survive the round trip" do
      leaves = [
        {"s", %{"columns" => ["txt", "n"], "rows" => [["it's got 'quotes'", nil], [nil, 5]]}}
      ]

      assert {:ok, %{"rows" => rows}} = Engine.run(leaves, [], "SELECT txt, n FROM s ORDER BY n NULLS FIRST")
      assert [["it's got 'quotes'", nil], [nil, 5]] = rows
    end
  end

  describe "hardening" do
    test "filesystem, extensions, ATTACH, COPY all die" do
      for hostile <- [
            "SELECT * FROM read_csv('/etc/passwd')",
            "SELECT * FROM glob('/*')",
            "INSTALL httpfs"
          ] do
        assert {:error, _} = Engine.run([], [], hostile), "expected #{hostile} to be rejected"
      end
    end

    test "the configuration is locked against the payload" do
      assert {:error, msg} = Engine.run([], [], "SET memory_limit='100GB'")
      # SET isn't even a SELECT — but even smuggled, the lock holds.
      assert is_binary(msg)
    end

    test "a runaway query is killed at the timeout" do
      started = System.monotonic_time(:millisecond)

      assert {:error, msg} =
               Engine.run([], [], "SELECT count(*) FROM range(100000000) a, range(10000) b")

      elapsed = System.monotonic_time(:millisecond) - started
      assert msg =~ "timed out"
      assert elapsed < 10_000
    end
  end
end
