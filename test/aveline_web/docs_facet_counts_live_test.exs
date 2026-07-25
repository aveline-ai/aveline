defmodule AvelineWeb.DocsFacetCountsLiveTest do
  use AvelineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aveline.Fixtures

  # Chip counts must cover the whole filtered corpus, not the rendered
  # page, and must not drift when more pages load.
  test "tag dropdown counts the corpus and Load more leaves counts unchanged", %{conn: conn} do
    owner = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(owner)

    page_size = Aveline.Pagination.default_page_size()
    total = page_size + 5

    for i <- 1..total do
      Fixtures.doc_fixture(ws, owner, slug: "prod-#{i}", tags: ["product"])
    end

    conn = conn |> Plug.Test.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, owner.id)
    {:ok, lv, _html} = live(conn, "/w/#{ws.slug}/docs")

    count_sel = ~s(#fdd-tag button[phx-value-tag="product"] .fdd-item-count)
    assert has_element?(lv, count_sel, "#{total}")

    render_click(lv, "load_more", %{})
    assert has_element?(lv, count_sel, "#{total}")
  end
end
