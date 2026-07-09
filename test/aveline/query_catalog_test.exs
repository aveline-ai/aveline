defmodule Aveline.QueryCatalogTest do
  @moduledoc """
  The query catalog context: raw + derived query CRUD, write-time
  reference and cycle validation, and end-to-end composition through
  the workspace source (leaves run against the test DB itself, joined
  and transformed in the sandboxed engine).
  """
  use Aveline.DataCase, async: false

  alias Aveline.DataSources
  alias Aveline.DataSources.Cache
  alias Aveline.DataSources.Catalog
  alias Aveline.DataSources.Engine
  alias Aveline.DataSources.Queries
  alias Aveline.Fixtures

  defp self_template do
    "postgres://#{System.get_env("PGUSER") || "postgres"}:<password>@#{System.get_env("PGHOST") || "localhost"}/aveline_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

  defp self_password, do: System.get_env("PGPASSWORD") || "postgres"

  setup do
    Cache.flush()
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    {:ok, src} = DataSources.create(ws.id, "self", self_template(), self_password(), user.id)
    %{user: user, ws: ws, src: src}
  end

  describe "workspace source seeding" do
    test "every workspace gets a built-in, credential-less source named 'derived'", %{ws: ws} do
      src = DataSources.workspace_source(ws.id)
      assert src.adapter == "workspace"
      assert src.name == "derived"
      assert %{"built_in" => true, "credential" => "none"} = DataSources.safe_map(src)
    end

    test "the built-in source can't be deleted, renamed, or shadowed by a user", %{ws: ws, user: user} do
      src = DataSources.workspace_source(ws.id)
      assert {:error, :workspace_source_immutable, _} = DataSources.delete(src, user.id)
      assert {:error, :workspace_source_immutable, _} = DataSources.edit(src, %{name: "x"}, user.id)

      assert {:error, :reserved_name, _} =
               DataSources.create(ws.id, "derived", self_template(), self_password(), user.id)
    end
  end

  describe "raw queries" do
    test "create names a live source", %{ws: ws, user: user} do
      assert {:ok, q} =
               Queries.create(ws.id, %{name: "ones", source: "self", sql: "select 1 as n"}, user.id)

      assert q.kind == "raw"
      assert q.data_source_id
    end

    test "unknown source is rejected", %{ws: ws, user: user} do
      assert {:error, :data_source_not_found, _} =
               Queries.create(ws.id, %{name: "x", source: "ghost", sql: "select 1"}, user.id)
    end

    test "raw over the built-in source is rejected (that's a derived query)", %{ws: ws, user: user} do
      assert {:error, :invalid_query, msg} =
               Queries.create(ws.id, %{name: "x", source: "derived", sql: "select 1"}, user.id)

      assert msg =~ "derived"
    end

    test "bad names are rejected at write time", %{ws: ws, user: user} do
      assert {:error, :invalid_query, _} =
               Queries.create(ws.id, %{name: "Has Spaces", source: "self", sql: "select 1"}, user.id)
    end
  end

  describe "derived queries" do
    setup %{ws: ws, user: user} do
      {:ok, _} =
        Queries.create(ws.id, %{name: "base_a", source: "self", sql: "select 1 as k, 10 as v"}, user.id)

      {:ok, _} =
        Queries.create(ws.id, %{name: "base_b", source: "self", sql: "select 1 as k, 5 as w"}, user.id)

      :ok
    end

    test "create parses and resolves references", %{ws: ws, user: user} do
      assert {:ok, q} =
               Queries.create(
                 ws.id,
                 %{name: "joined", sql: "select a.k, a.v + b.w AS total FROM base_a a JOIN base_b b USING (k)"},
                 user.id
               )

      assert q.kind == "derived"
    end

    test "referencing an unknown catalog query is rejected", %{ws: ws, user: user} do
      assert {:error, :invalid_query, msg} =
               Queries.create(ws.id, %{name: "bad", sql: "select * FROM nonexistent"}, user.id)

      assert msg =~ "unknown catalog"
    end

    test "non-SELECT / syntax errors are rejected", %{ws: ws, user: user} do
      assert {:error, :invalid_query, _} =
               Queries.create(ws.id, %{name: "bad", sql: "drop table base_a"}, user.id)
    end

    test "chains are allowed; a cycle is rejected", %{ws: ws, user: user} do
      {:ok, _} = Queries.create(ws.id, %{name: "lvl1", sql: "select k, v FROM base_a"}, user.id)
      {:ok, _} = Queries.create(ws.id, %{name: "lvl2", sql: "select k, v FROM lvl1"}, user.id)

      # Editing lvl1 to read lvl2 would close lvl1→lvl2→lvl1.
      current = Queries.get_current_by_name(ws.id, "lvl1")

      assert {:error, :invalid_query, msg} =
               Queries.edit(current, %{sql: "select k, v FROM lvl2"}, user.id)

      assert msg =~ "circular"
    end

    test "a query with derived dependents can't be renamed or deleted", %{ws: ws, user: user} do
      {:ok, _} = Queries.create(ws.id, %{name: "leaf", sql: "select k FROM base_a"}, user.id)
      {:ok, _} = Queries.create(ws.id, %{name: "onleaf", sql: "select k FROM leaf"}, user.id)

      leaf = Queries.get_current_by_name(ws.id, "leaf")
      assert {:error, :query_has_dependents, _} = Queries.delete(leaf, user.id)
      assert {:error, :query_has_dependents, _} = Queries.edit(leaf, %{name: "renamed"}, user.id)
    end
  end

  describe "end-to-end composition through the workspace source" do
    @describetag skip: unless(Engine.available?(), do: "duckdb not fetched")

    test "a derived query joins two raw sources and a chart runs it", %{ws: ws, user: user} do
      {:ok, _} =
        Queries.create(
          ws.id,
          %{name: "signups", source: "self", sql: "select 1 as week, 10 as n union all select 2, 14"},
          user.id
        )

      {:ok, _} =
        Queries.create(
          ws.id,
          %{name: "spend", source: "self", sql: "select 1 as week, 100 as dollars union all select 2, 120"},
          user.id
        )

      {:ok, _} =
        Queries.create(
          ws.id,
          %{
            name: "cac",
            sql: "select s.week, d.dollars::double / s.n AS cost FROM signups s JOIN spend d USING (week) ORDER BY week"
          },
          user.id
        )

      assert {:ok, %{"columns" => ["week", "cost"], "rows" => rows}} =
               Catalog.run(ws.id, "select week, cost FROM cac ORDER BY week")

      assert [[1, 10.0], [2, _]] = rows
    end

    test "regression over a MySQL-style dialect-poor source works (compute is ours)", %{
      ws: ws,
      user: user
    } do
      {:ok, _} =
        Queries.create(
          ws.id,
          %{name: "series", source: "self", sql: "select g as x, g * 2 as y from generate_series(1,5) as t(g)"},
          user.id
        )

      assert {:ok, %{"rows" => [[slope]]}} =
               Catalog.run(ws.id, "select regr_slope(y, x) AS slope FROM series")

      assert_in_delta slope, 2.0, 0.0001
    end

    test "unknown table in workspace SQL fails closed with a helpful error", %{ws: ws} do
      assert {:error, msg} = Catalog.run(ws.id, "select * FROM not_a_query")
      assert msg =~ "unknown table"
    end
  end
end
