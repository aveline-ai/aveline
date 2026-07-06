defmodule AvelineWeb.WorkspaceGateTest do
  use AvelineWeb.ConnCase, async: false

  alias Aveline.Fixtures

  setup do
    owner = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(owner)
    doc = Fixtures.doc_fixture(ws, owner, slug: "secret-plan", title: "The secret plan")
    %{owner: owner, ws: ws, doc: doc}
  end

  defp login(conn, user) do
    conn |> Plug.Test.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, user.id)
  end

  test "unauthenticated doc URL renders the gate AT the URL with generic OG tags", %{
    conn: conn,
    ws: ws
  } do
    conn = get(conn, "/w/#{ws.slug}/d/secret-plan")
    html = html_response(conn, 200)

    # No redirect, generic unfurl metadata, nothing about the doc.
    assert html =~ ~s(property="og:title" content="A private doc on Aveline")
    assert html =~ ~s(name="robots" content="noindex")
    assert html =~ "This doc is private"
    assert html =~ "/login?next=" <> URI.encode_www_form("/w/#{ws.slug}/d/secret-plan")
    refute html =~ "The secret plan"
    refute html =~ "Sign up"
  end

  test "workspace URLs gate with workspace wording", %{conn: conn, ws: ws} do
    html = conn |> get("/w/#{ws.slug}") |> html_response(200)
    assert html =~ ~s(property="og:title" content="A private workspace on Aveline")
    assert html =~ "This workspace is private"
  end

  test "signed-in non-member gets the no-access gate; nonexistent workspaces look identical", %{
    conn: conn,
    ws: ws
  } do
    other = Fixtures.user_fixture()

    real = conn |> login(other) |> get("/w/#{ws.slug}/d/secret-plan") |> html_response(200)
    assert real =~ "You don't have access to this workspace"
    refute real =~ "The secret plan"

    ghost =
      build_conn() |> login(other) |> get("/w/no-such-workspace/d/whatever") |> html_response(200)

    assert ghost =~ "You don't have access to this workspace"
  end

  test "members pass through to the doc", %{conn: conn, owner: owner, ws: ws} do
    html = conn |> login(owner) |> get("/w/#{ws.slug}/d/secret-plan") |> html_response(200)
    assert html =~ "The secret plan"
    refute html =~ "This doc is private"
  end
end
