defmodule AvelineWeb.Api.DocKudosApiTest do
  @moduledoc """
  Kudos toggle over HTTP — integration coverage for the Gleam handler
  (src/aveline/handlers/doc_kudos.gleam) + CtxBuilder boundary. Behavior
  must match the pre-Gleam endpoint exactly.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  setup %{conn: conn} do
    owner = user_fixture()
    other = user_fixture()
    ws = workspace_fixture(owner)
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)
    doc = doc_fixture(ws, owner, title: "Helpful doc")

    {_t, owner_token} = token_fixture(owner)
    {_t, other_token} = token_fixture(other)

    as = fn token ->
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
    end

    {:ok, owner_conn: as.(owner_token), other_conn: as.(other_token), ws: ws, doc: doc, other: other}
  end

  test "toggle gives then revokes, with counts", %{other_conn: conn, ws: ws, doc: doc} do
    body = conn |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/kudos") |> json_response(200)
    assert body["given_by_me"] == true
    assert body["count"] == 1

    body = conn |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/kudos") |> json_response(200)
    assert body["given_by_me"] == false
    assert body["count"] == 0
  end

  test "own doc rejects self kudos", %{owner_conn: conn, ws: ws, doc: doc} do
    body = conn |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/kudos") |> json_response(422)
    assert body["error"]["code"] == "self_kudos"
  end

  test "unknown slug is 404", %{other_conn: conn, ws: ws} do
    assert conn |> post(~p"/api/workspaces/#{ws.slug}/docs/nope/kudos") |> json_response(404)
  end

  test "private doc is invisible to non-shared member", %{owner_conn: owner_conn, other_conn: other_conn, ws: ws, doc: doc} do
    owner_conn
    |> put(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/visibility", %{"visibility" => "private"})
    |> json_response(200)

    assert other_conn |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/kudos") |> json_response(404)
  end

  test "kudos toggle records activity events", %{other_conn: conn, ws: ws, doc: doc, other: other} do
    conn |> post(~p"/api/workspaces/#{ws.slug}/docs/#{doc.slug}/kudos") |> json_response(200)

    events = conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)

    assert Enum.any?(events["events"], fn e ->
             e["action"] == "kudos_given" and get_in(e, ["actor", "user", "username"]) == other.username
           end)
  end
end
