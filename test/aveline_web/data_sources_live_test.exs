defmodule AvelineWeb.DataSourcesLiveTest do
  @moduledoc """
  The query-aware data sources UI: one page. Source cards filter the
  catalog; query cards open a modal with description, SQL, and lineage
  chips (built on / feeds) that jump between queries. The old per-source
  detail URLs redirect back to the list.
  """
  use AvelineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aveline.DataSources
  alias Aveline.DataSources.Queries
  alias Aveline.Fixtures

  defp self_template do
    "postgres://#{System.get_env("PGUSER") || "postgres"}:<password>@#{System.get_env("PGHOST") || "localhost"}/aveline_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

  defp self_password, do: System.get_env("PGPASSWORD") || "postgres"

  setup %{conn: conn} do
    owner = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(owner)
    {:ok, _src} = DataSources.create(ws.id, "self", self_template(), self_password(), owner.id)
    {:ok, _} = Queries.create(ws.id, %{name: "docs_ct", source: "self", sql: "select count(*) AS n FROM docs"}, owner.id)
    {:ok, _} = Queries.create(ws.id, %{name: "docs_view", sql: "select n FROM docs_ct"}, owner.id)

    conn = conn |> Plug.Test.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, owner.id)
    %{conn: conn, ws: ws, owner: owner}
  end

  test "list shows per-source query counts and the workspace catalog row", %{conn: conn, ws: ws} do
    {:ok, _lv, html} = live(conn, ~p"/w/#{ws.slug}/data-sources")

    assert html =~ "self"
    # one raw query built on `self` (number is bold in the card foot)
    assert html =~ "<strong>1</strong> query"
    # the built-in catalog card shows its engine (duckdb), not "workspace"
    assert html =~ "duckdb"
    assert html =~ "built-in"
    # the query catalog section lists both queries with the search box
    assert html =~ "Query catalog"
    assert html =~ "Search queries"
    assert html =~ "docs_view"
    # no descriptions yet — the nudge shows
    assert html =~ "No description yet"
  end

  test "catalog search filters by name and description", %{conn: conn, ws: ws, owner: owner} do
    {:ok, q} = Queries.get_current_by_name(ws.id, "docs_ct") |> then(&{:ok, &1})

    {:ok, _} =
      Queries.edit(q, %{description: "How many docs the workspace holds."}, owner.id)

    {:ok, lv, _html} = live(conn, ~p"/w/#{ws.slug}/data-sources")

    html = render_change(lv, "search", %{"q" => "how many docs"})
    assert html =~ "docs_ct"
    refute html =~ "docs_view"

    html = render_change(lv, "search", %{"q" => "zebra"})
    assert html =~ "Nothing matches"
  end

  test "opening a query shows its SQL, lineage chips, and jumps between queries", %{conn: conn, ws: ws} do
    {:ok, lv, _html} = live(conn, ~p"/w/#{ws.slug}/data-sources")

    # docs_ct: a raw leaf that feeds the derived docs_view. The open
    # query is URL state so back/forward walks the jump history.
    html = render_click(lv, "open_query", %{"name" => "docs_ct"})
    assert_patch(lv, "/w/#{ws.slug}/data-sources?query=docs_ct")
    assert html =~ "qm-sql-docs_ct"
    assert html =~ "feeds"
    assert html =~ "docs_view"

    # Jump downstream via the chip's event: the modal swaps to docs_view,
    # which shows what it's built on.
    html = render_click(lv, "open_query", %{"name" => "docs_view"})
    assert_patch(lv, "/w/#{ws.slug}/data-sources?query=docs_view")
    assert html =~ "qm-sql-docs_view"
    assert html =~ "built on"
    assert html =~ "docs_ct"

    html = render_click(lv, "close_query", %{})
    assert_patch(lv, "/w/#{ws.slug}/data-sources")
    refute html =~ "qm-sql-"
  end

  test "a ?query= URL deep-links straight into the modal", %{conn: conn, ws: ws} do
    {:ok, _lv, html} = live(conn, ~p"/w/#{ws.slug}/data-sources?query=docs_view")
    assert html =~ "qm-sql-docs_view"

    # Unknown names just render the page, no modal.
    {:ok, _lv, html} = live(conn, ~p"/w/#{ws.slug}/data-sources?query=ghost")
    refute html =~ "qm-sql-"
  end

  test "clicking a source filters the catalog to it; clicking again clears", %{conn: conn, ws: ws} do
    src = DataSources.get_current_by_name(ws.id, "self")
    {:ok, lv, _html} = live(conn, ~p"/w/#{ws.slug}/data-sources")

    html = render_click(lv, "filter_source", %{"base" => src.base_data_source_id})
    assert html =~ "docs_ct"
    refute html =~ "qm-sql-"
    # the derived query is not on `self`, so it's filtered out
    refute html =~ ">docs_view<"
    assert html =~ "filtering"

    html = render_click(lv, "filter_source", %{"base" => src.base_data_source_id})
    assert html =~ "docs_view"
    refute html =~ "filtering"
  end

  test "old per-source detail URLs redirect to the list", %{conn: conn, ws: ws} do
    conn = get(conn, ~p"/w/#{ws.slug}/data-sources/derived")
    assert redirected_to(conn) == "/w/#{ws.slug}/data-sources"
  end
end
