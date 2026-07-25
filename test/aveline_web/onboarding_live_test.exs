defmodule AvelineWeb.OnboardingLiveTest do
  @moduledoc """
  The vestibule as a place: /w/:slug/welcome. Joining flows land there
  once; the sidebar's Connect CTA is the way back from anywhere;
  leaving is just navigation. Home is always home.
  """
  use AvelineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aveline.DocViews
  alias Aveline.Docs
  alias Aveline.Fixtures
  alias Aveline.Onboarding

  setup %{conn: conn} do
    owner = Fixtures.user_fixture()
    # workspace_fixture seeds the orientation doc.
    ws = Fixtures.workspace_fixture(owner)

    conn = conn |> Plug.Test.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, owner.id)
    %{conn: conn, ws: ws, owner: owner}
  end

  defp connect_agent(ws, user) do
    orientation = Docs.get_orientation(ws.id)
    DocViews.record(ws.id, orientation.base_doc_id, user.id, "agent")
  end

  test "connected? derives from an agent orientation read, humans don't count", %{
    ws: ws,
    owner: owner
  } do
    refute Onboarding.agent_connected?(ws.id, owner.id)

    orientation = Docs.get_orientation(ws.id)
    DocViews.record(ws.id, orientation.base_doc_id, owner.id, "human")
    refute Onboarding.agent_connected?(ws.id, owner.id)

    connect_agent(ws, owner)
    assert Onboarding.agent_connected?(ws.id, owner.id)
  end

  test "welcome renders the vestibule; home stays home; sidebar carries the CTA", %{
    conn: conn,
    ws: ws
  } do
    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/welcome")

    assert html =~ ~s(class="welcome-stage)
    assert html =~ "Welcome to"
    assert html =~ "starts here"
    # Steps are visible up front: nothing hides behind toggles.
    refute html =~ "view the prompt"
    assert html =~ "or do it yourself"
    assert html =~ "Mint a fresh one anytime in"

    # Home is a normal dashboard with the sidebar CTA, no setup card.
    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}")
    assert html =~ "Welcome back,"
    assert html =~ "Connect your agent"
    assert html =~ "/w/#{ws.slug}/welcome"
    refute html =~ ~s(class="welcome-stage)
  end

  test "connecting on the welcome page offers Take me in; connected users bounce", %{
    conn: conn,
    ws: ws,
    owner: owner
  } do
    {:ok, lv, _html} = live(conn, "/w/#{ws.slug}/welcome")

    connect_agent(ws, owner)
    send(lv.pid, :check_setup)
    html = render(lv)
    assert html =~ "Your agent is in"
    assert html =~ "Take me in"

    # Once connected, /welcome bounces straight home and the sidebar
    # CTA is gone everywhere.
    {:error, {:live_redirect, %{to: to}}} = live(conn, "/w/#{ws.slug}/welcome")
    assert to == "/w/#{ws.slug}"

    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}")
    refute html =~ "Connect your agent"
  end

  test "an invited member gets the same welcome, with the team visible", %{ws: ws} do
    invitee = Fixtures.user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, invitee.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, invitee.id)

    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/welcome")
    assert html =~ ~s(class="welcome-stage)
    assert html =~ "saved you a seat"
    assert html =~ "is here"
    assert html =~ "Start with"
    # Prompt is tool-agnostic and stays in the DOM as the copy source.
    assert html =~ "Claude Code, Cursor, and Codex all work"
    assert html =~ "If it errors, ask me to run"
  end

  test "settings always carries the section: full card before, quiet line + reclaim after", %{
    conn: conn,
    ws: ws,
    owner: owner
  } do
    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/settings")
    assert html =~ "Connect your agent"
    assert html =~ "Listening for your agent"

    connect_agent(ws, owner)

    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/settings")
    assert html =~ "Connect your agent"
    assert html =~ "✓ Connected"
    assert html =~ "Setting up another machine?"
    refute html =~ "Listening for your agent…"
  end
end
