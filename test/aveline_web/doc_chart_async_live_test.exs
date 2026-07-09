defmodule AvelineWeb.DocChartAsyncLiveTest do
  @moduledoc """
  The LiveView half of the async chart engine: docs mount instantly with
  placeholder cards, results stream in via handle_async, errors carry a
  retry, and historical versions idle instead of auto-running.
  """
  use AvelineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aveline.DataSources
  alias Aveline.Docs
  alias Aveline.Fixtures

  defp self_template do
    "postgres://#{System.get_env("PGUSER") || "postgres"}:<password>@#{System.get_env("PGHOST") || "localhost"}/aveline_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

  defp self_password, do: System.get_env("PGPASSWORD") || "postgres"

  setup %{conn: conn} do
    Aveline.DataSources.Cache.flush()
    owner = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(owner)
    {:ok, _ds} = DataSources.create(ws.id, "self", self_template(), self_password(), owner.id)

    conn = conn |> Plug.Test.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, owner.id)
    %{conn: conn, ws: ws, owner: owner}
  end

  # Create a named raw query on `self` and return a chart block for it.
  defp chart(ws, owner, name, sql) do
    Fixtures.query_fixture(ws, owner, name, sql, source: "self")
    Fixtures.chart_block(name)
  end

  test "doc mounts with a placeholder and the chart streams in", %{conn: conn, ws: ws, owner: owner} do
    Fixtures.doc_fixture(ws, owner, slug: "metrics", blocks: [chart(ws, owner, "answer_q", "select 41 + 1 as answer")])

    {:ok, lv, html} = live(conn, "/w/#{ws.slug}/d/metrics")

    # Mount never ran the query: placeholder is up, data isn't. (The SQL
    # pane always shows the query text, so assert on the data cell.)
    assert html =~ "running query"
    refute html =~ "<td>42</td>"

    html = render_async(lv, 30_000)
    refute html =~ "running query"
    assert html =~ "<td>42</td>"
    assert html =~ "refresh"
  end

  test "bad SQL streams in as an error card with a retry", %{conn: conn, ws: ws, owner: owner} do
    Fixtures.doc_fixture(ws, owner, slug: "broken", blocks: [chart(ws, owner, "broken_q", "select nope from nowhere")])

    {:ok, lv, html} = live(conn, "/w/#{ws.slug}/d/broken")
    assert html =~ "running query"

    html = render_async(lv, 30_000)
    assert html =~ "try again"
    refute html =~ "running query"
  end

  test "charts sharing a query share one run (and one result)", %{conn: conn, ws: ws, owner: owner} do
    Fixtures.query_fixture(ws, owner, "stamp_q", "select clock_timestamp()::text as t", source: "self")
    twin = Fixtures.chart_block("stamp_q")
    Fixtures.doc_fixture(ws, owner, slug: "twins", blocks: [twin, twin])

    {:ok, lv, _html} = live(conn, "/w/#{ws.slug}/d/twins")
    html = render_async(lv, 30_000)

    stamps =
      ~r/<td>(\d{4}-\d{2}-\d{2} [^<]+)<\/td>/
      |> Regex.scan(html, capture: :all_but_first)
      |> List.flatten()

    assert length(stamps) == 2
    assert [_one] = Enum.uniq(stamps)
  end

  test "historical versions idle; a click runs them", %{conn: conn, ws: ws, owner: owner} do
    doc = Fixtures.doc_fixture(ws, owner, slug: "old", blocks: [chart(ws, owner, "seven_q", "select 7 as seven")])

    {:ok, _v2} =
      Docs.replace_blocks(
        doc,
        [%{"type" => "paragraph", "content" => [%{"text" => "chart removed"}]}],
        %{actor_user_id: owner.id, actor_type: "human"},
        intent: "drop the chart"
      )

    {:ok, lv, html} = live(conn, "/w/#{ws.slug}/d/old?version=1")

    # No auto-run on time travel: idle control, no spinner, no data.
    assert html =~ "Run query"
    assert html =~ "historical version"
    refute html =~ "running query"
    refute html =~ "<td>7</td>"

    lv |> element("button.chart-run-btn") |> render_click()
    html = render_async(lv, 30_000)
    assert html =~ "<td>7</td>"
  end
end
