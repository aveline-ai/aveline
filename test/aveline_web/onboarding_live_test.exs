defmodule AvelineWeb.OnboardingLiveTest do
  @moduledoc """
  Agent-connected is a state, not a screen: the setup card follows the
  user across home and settings until an agent under their account
  reads the orientation doc, then evaporates. Closes the invited-users
  gap by construction: joiners land on home, home covers anyone
  unconnected.
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

  test "home is the vestibule until connect or skip; skip drops into the dashboard", %{
    conn: conn,
    ws: ws,
    owner: owner
  } do
    {:ok, lv, html} = live(conn, "/w/#{ws.slug}")

    # The vestibule replaces home: welcome, one action, no shelves.
    assert html =~ ~s(class="welcome-stage")
    assert html =~ "Welcome to"
    assert html =~ "starts here"
    assert html =~ "or look around first"
    refute html =~ "Welcome back,"

    # Look around first = skip: the dashboard appears, compact card on top.
    render_click(element(lv, ".setup-skip"))
    refute render(lv) =~ ~s(class="welcome-stage")
    assert render(lv) =~ "Welcome back,"
    assert render(lv) =~ "Connect your agent"
    assert Aveline.Workspaces.setup_skipped?(ws.id, owner.id)

    # Durable across visits.
    {:ok, lv, html} = live(conn, "/w/#{ws.slug}")
    refute html =~ ~s(class="welcome-stage")
    assert html =~ "Connect your agent"
    assert html =~ "Waiting for your agent to read the orientation doc"

    # Agent connects; the poll tick flips the card to its done state.
    connect_agent(ws, owner)
    send(lv.pid, :check_setup)
    assert render(lv) =~ "You&#39;re connected"

    # Next visit: no setup surface at all.
    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}")
    refute html =~ "Connect your agent"
  end

  test "connecting inside the vestibule offers Take me in", %{
    conn: conn,
    ws: ws,
    owner: owner
  } do
    {:ok, lv, _html} = live(conn, "/w/#{ws.slug}")

    connect_agent(ws, owner)
    send(lv.pid, :check_setup)
    html = render(lv)
    assert html =~ "Your agent is in"
    assert html =~ "Take me in"

    render_click(element(lv, ".welcome-enter"))
    html = render(lv)
    assert html =~ "Welcome back,"
    refute html =~ ~s(class="welcome-stage")
  end

  test "an invited member landing on home gets the card too", %{ws: ws} do
    invitee = Fixtures.user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, invitee.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, invitee.id)

    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}")
    assert html =~ ~s(class="welcome-stage")
    # Proof of life: the team and the one pointer doc.
    assert html =~ "is here"
    assert html =~ "Start with"
    # Existing-user variant: login is conditional, never demanded.
    assert html =~ "If it errors, ask me to run"
  end

  test "settings always carries the section: full card before, quiet line + reclaim after", %{
    conn: conn,
    ws: ws,
    owner: owner
  } do
    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/settings")
    assert html =~ "Connect your agent"
    assert html =~ "Waiting for your agent to read the orientation doc"

    connect_agent(ws, owner)

    {:ok, _lv, html} = live(conn, "/w/#{ws.slug}/settings")
    assert html =~ "Connect your agent"
    assert html =~ "✓ Connected"
    assert html =~ "Setting up another machine?"
    refute html =~ "Waiting for your agent to read the orientation doc"
  end
end
