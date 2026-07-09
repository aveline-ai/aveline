defmodule AvelineWeb.DataSourcesLiveTest do
  @moduledoc """
  The query-aware data sources UI: the list shows per-source query +
  chart counts and links into a detail page; the detail page shows the
  queries built on a source (lineage) and the docs that chart it. The
  workspace source is presented as the catalog.
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
    # one raw query built on `self`
    assert html =~ "1 query"
    # the built-in catalog row, presented as such (not "workspace · workspace")
    assert html =~ "workspace catalog"
    assert html =~ "built-in"
    # its one derived query
    assert html =~ "1 query"
  end

  test "clicking a source opens its detail page with lineage", %{conn: conn, ws: ws} do
    {:ok, _lv, html} = live(conn, ~p"/w/#{ws.slug}/data-sources/self")

    assert html =~ "Queries built on this source"
    assert html =~ "docs_ct"
    assert html =~ "raw"
    # docs_ct feeds the derived docs_view — lineage shown
    assert html =~ "feeds"
    assert html =~ "docs_view"
  end

  test "the workspace source detail shows the derived catalog", %{conn: conn, ws: ws} do
    {:ok, _lv, html} = live(conn, ~p"/w/#{ws.slug}/data-sources/workspace")

    assert html =~ "Catalog queries"
    assert html =~ "docs_view"
    assert html =~ "derived"
  end

  test "unknown source redirects back to the list", %{conn: conn, ws: ws} do
    assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/w/#{ws.slug}/data-sources/ghost")
    assert path == "/w/#{ws.slug}/data-sources"
  end
end
