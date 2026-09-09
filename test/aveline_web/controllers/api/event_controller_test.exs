defmodule AvelineWeb.Api.EventControllerTest do
  @moduledoc """
  Activity feed over HTTP — integration coverage for the Gleam handler
  (src/aveline/handlers/events.gleam) + the coarse listing cap.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_t, plaintext} = token_fixture(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext}")
      |> put_req_header("accept", "application/json")

    {:ok, conn: conn, user: user, ws: ws}
  end

  defp record!(ws, user, action) do
    :ok =
      Aveline.Events.record(%{
        workspace_id: ws.id,
        actor: user.id,
        actor_type: "human",
        action: action,
        target_kind: "doc",
        target_id: Ecto.UUID.generate(),
        target_label: action
      })
  end

  test "index returns newest-first events with actor and cursor", %{conn: conn, ws: ws, user: user} do
    record!(ws, user, "first")
    record!(ws, user, "second")

    body = conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)

    assert body["ok"] == true
    actions = Enum.map(body["events"], & &1["action"])
    # Workspace creation itself seeds events; ours are the newest.
    assert ["second", "first" | _] = actions

    [newest | _] = body["events"]
    assert newest["actor"]["type"] == "human"
    assert newest["actor"]["user"]["username"] == user.username
    assert newest["target_label"] == "second"
    assert is_map(newest["data"])
    assert body["next_before_id"] == List.last(body["events"])["id"]
  end

  test "limit is parsed and capped; garbage falls back to 50", %{conn: conn, ws: ws, user: user} do
    for n <- 1..3, do: record!(ws, user, "e#{n}")

    body = conn |> get(~p"/api/workspaces/#{ws.slug}/events?limit=2") |> json_response(200)
    assert length(body["events"]) == 2

    body = conn |> get(~p"/api/workspaces/#{ws.slug}/events?limit=abc") |> json_response(200)
    assert length(body["events"]) >= 3

    body = conn |> get(~p"/api/workspaces/#{ws.slug}/events?limit=9999") |> json_response(200)
    assert length(body["events"]) >= 3
  end

  test "before_id pages without repeating the anchor", %{conn: conn, ws: ws, user: user} do
    for n <- 1..4, do: record!(ws, user, "page#{n}")

    first = conn |> get(~p"/api/workspaces/#{ws.slug}/events?limit=2") |> json_response(200)
    assert [%{"action" => "page4"}, %{"action" => "page3"}] = first["events"]

    second =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/events?limit=2&before_id=#{first["next_before_id"]}")
      |> json_response(200)

    assert [%{"action" => "page2"}, %{"action" => "page1"}] = second["events"]

    # An unknown/empty cursor is ignored, not an error.
    assert conn
           |> get(~p"/api/workspaces/#{ws.slug}/events?before_id=")
           |> json_response(200)
  end
end
