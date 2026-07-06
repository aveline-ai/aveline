defmodule AvelineWeb.DocsViewsLiveTest do
  use AvelineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aveline.Fixtures
  alias Aveline.Views

  setup %{conn: conn} do
    owner = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(owner)

    # Two tickets in different status columns + one untagged doc.
    Fixtures.doc_fixture(ws, owner, slug: "t-one", title: "Ticket one", tags: ["ticket", "status:todo"])
    Fixtures.doc_fixture(ws, owner, slug: "t-two", title: "Ticket two", tags: ["ticket", "status:done"])
    Fixtures.doc_fixture(ws, owner, slug: "plain", title: "Plain doc")

    {:ok, view} =
      Views.create(ws.id, "tickets", "All open work by status.", %{
        "tags" => ["ticket"],
        "group_by" => "status"
      }, owner.id)

    {:ok, _} = Views.set_pinned(view, true)

    conn = conn |> Plug.Test.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, owner.id)
    %{conn: conn, ws: ws, owner: owner}
  end

  test "docs page lists everything, shows the switcher, sidebar carries the pinned view", %{
    conn: conn,
    ws: ws
  } do
    {:ok, lv, html} = live(conn, "/w/#{ws.slug}/docs")

    assert html =~ "Ticket one"
    assert html =~ "Plain doc"
    # Title menu carries All docs (active) + the view.
    assert has_element?(lv, ".title-fdd-btn", "Docs")
    assert has_element?(lv, "#fdd-view-menu .vmenu-item .fdd-check.on + .vmenu-body .vmenu-name", "All docs")
    assert has_element?(lv, "#fdd-view-menu .vmenu-name", "tickets")
    # Sidebar section carries the pinned view.
    assert has_element?(lv, ".sidebar-views .sidebar-item", "tickets")
  end

  test "group param turns the docs list into a kanban", %{conn: conn, ws: ws} do
    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/docs?group=status")

    assert html =~ "group-head-name"
    assert html =~ "todo"
    assert html =~ "done"
    # The untagged doc lands in the trailing unassigned section.
    assert html =~ "no status"
    assert html =~ "Plain doc"
  end

  test "a pristine view seeds knobs from config, no modified chip", %{conn: conn, ws: ws} do
    {:ok, lv, html} = live(conn, "/w/#{ws.slug}/v/tickets")

    # Title + description from the view; kanban from group_by; filtered set.
    assert has_element?(lv, ".page-title", "tickets")
    assert html =~ "All open work by status."
    assert has_element?(lv, ".group-head-name", "todo")
    assert html =~ "Ticket one"
    refute html =~ "Plain doc"
    refute has_element?(lv, ".view-modified")
  end

  test "deviating from the view shows modified + reset returns to pristine", %{conn: conn, ws: ws} do
    {:ok, lv, _html} = live(conn, "/w/#{ws.slug}/v/tickets?group=none&tag[]=ticket")

    assert has_element?(lv, ".view-modified")

    # Reset patches back to the bare view URL → pristine again.
    lv |> element("button.view-reset") |> render_click()
    refute has_element?(lv, ".view-modified")
    assert has_element?(lv, ".group-head-name", "todo")
  end

  test "session knobs work inside a view without touching it", %{conn: conn, ws: ws} do
    {:ok, lv, _html} = live(conn, "/w/#{ws.slug}/v/tickets")

    # Ungroup via the group control: kanban becomes a list, view marked modified.
    render_click(lv, "set_group", %{"group" => "none"})
    refute has_element?(lv, ".group-head-name")
    assert has_element?(lv, ".view-modified")

    # Saved view unchanged.
    assert Views.get_current_by_name(ws.id, "tickets").config["group_by"] == "status"
  end

  test "unknown view redirects to docs with a flash", %{conn: conn, ws: ws} do
    assert {:error, {:live_redirect, %{to: to}}} = live(conn, "/w/#{ws.slug}/v/ghost")
    assert to == "/w/#{ws.slug}/docs"
  end
end
