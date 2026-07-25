defmodule AvelineWeb.OnboardingLiveTest do
  @moduledoc """
  The welcome page: a plain destination at /w/:slug/welcome. Joining
  flows land there; the sidebar's Connect agent item (always present)
  is the way back; no connected-state machinery anywhere.
  """
  use AvelineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aveline.Fixtures

  setup %{conn: conn} do
    owner = Fixtures.user_fixture()
    # workspace_fixture seeds the orientation doc.
    ws = Fixtures.workspace_fixture(owner)

    conn = conn |> Plug.Test.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, owner.id)
    %{conn: conn, ws: ws, owner: owner}
  end

  test "welcome renders the setup page; home stays home; sidebar always links it", %{
    conn: conn,
    ws: ws
  } do
    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/welcome")

    assert html =~ ~s(class="welcome-stage)
    assert html =~ "Welcome to"
    assert html =~ "starts here"
    assert html =~ "or do it yourself"
    assert html =~ "Mint a fresh one anytime in"
    assert html =~ "Teach your project"
    # Tool-agnostic prompt rides along as the hidden copy source.
    assert html =~ "Claude Code, Cursor, and Codex all work"
    assert html =~ "If it errors, ask me to run"

    # Home is a normal dashboard; the sidebar carries Connect agent
    # unconditionally.
    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}")
    assert html =~ "Welcome back,"
    assert html =~ "Connect agent"
    assert html =~ "/w/#{ws.slug}/welcome"
    refute html =~ ~s(class="welcome-stage)
  end

  test "an invited member gets the inhabited welcome with the team visible", %{ws: ws} do
    invitee = Fixtures.user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, invitee.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, invitee.id)

    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/welcome")
    assert html =~ ~s(class="welcome-stage)
    assert html =~ "already knows things"
    assert html =~ "is here"
    assert html =~ "Start with"
    refute html =~ "starts here"
  end

  test "fresh workspaces sell compounding without fake proof", %{conn: conn, ws: ws} do
    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/welcome")

    # Solo owner: fresh mode. Compounding pitch, no proof row, no
    # backdrop cards built from seed docs.
    assert html =~ "starts here"
    assert html =~ "compounds"
    refute html =~ "saved views"
    refute html =~ ~s(class="wb-card)
  end
end
