defmodule AvelineWeb.Api.MessageControllerTest do
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_t, plaintext} = token_fixture(user)
    conn = conn |> put_req_header("authorization", "Bearer #{plaintext}")

    item =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/items", %{title: "Test", slug: "test"})
      |> json_response(201)

    {:ok, conn: conn, user: user, ws: ws, item: item}
  end

  test "create + index + soft delete", %{conn: conn, ws: ws, item: item} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/items/#{item["slug"]}/messages", %{body: "first reply"})
      |> json_response(201)

    assert body["body"] == "first reply"
    assert body["author"]["username"]
    assert body["created_via"] == "web"

    idx =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/items/#{item["slug"]}/messages")
      |> json_response(200)

    assert length(idx["messages"]) == 1

    _ =
      conn
      |> delete(~p"/api/workspaces/#{ws.slug}/items/#{item["slug"]}/messages/#{body["id"]}")
      |> json_response(200)

    after_delete =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/items/#{item["slug"]}/messages")
      |> json_response(200)

    assert after_delete["messages"] == []
  end

  test "update sets edited_at", %{conn: conn, ws: ws, item: item} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/items/#{item["slug"]}/messages", %{body: "v1"})
      |> json_response(201)

    refute body["edited_at"]

    updated =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/items/#{item["slug"]}/messages/#{body["id"]}", %{body: "v2"})
      |> json_response(200)

    assert updated["body"] == "v2"
    assert updated["edited_at"]
  end

  test "validation_failed for empty body", %{conn: conn, ws: ws, item: item} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/items/#{item["slug"]}/messages", %{body: ""})
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
  end

  test "404 on missing item", %{conn: conn, ws: ws} do
    body =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/items/nope/messages")
      |> json_response(404)

    assert body["error"]["code"] == "not_found"
  end

  test "broadcasts message_created to the item's topic", %{conn: conn, ws: ws, item: item} do
    Aveline.Broadcasts.subscribe("item:" <> item["id"] <> ":messages")

    _ =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/items/#{item["slug"]}/messages", %{body: "hi"})
      |> json_response(201)

    assert_receive {:message_created, %Aveline.Messages.ItemMessage{body: "hi"}}, 1_000
  end
end
