defmodule AvelineWeb.Api.ViewControllerTest do
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_t, plaintext} = token_fixture(user)
    conn = conn |> put_req_header("authorization", "Bearer #{plaintext}")
    {:ok, conn: conn, user: user, ws: ws}
  end

  test "create + show + index + items", %{conn: conn, ws: ws} do
    _ =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/items", %{
        title: "a",
        slug: "a",
        tags: ["oncall"],
        actor: "agent",
        blocks: [%{type: "paragraph", content: [%{text: "a"}]}]
      })

    _ =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/items", %{
        title: "b",
        slug: "b",
        tags: ["other"],
        actor: "agent",
        blocks: [%{type: "paragraph", content: [%{text: "b"}]}]
      })

    payload = %{slug: "oncall", name: "Oncall", tag_filter: ["oncall"]}
    body = conn |> post(~p"/api/workspaces/#{ws.slug}/views", payload) |> json_response(201)
    assert body["slug"] == "oncall"

    show = conn |> get(~p"/api/workspaces/#{ws.slug}/views/oncall") |> json_response(200)
    assert show["view"]["slug"] == "oncall"
    assert length(show["items"]) == 1
    assert hd(show["items"])["title"] == "a"

    idx = conn |> get(~p"/api/workspaces/#{ws.slug}/views") |> json_response(200)
    assert length(idx["views"]) == 1
  end

  test "tag_invalid for bad tag_filter", %{conn: conn, ws: ws} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/views", %{slug: "bad", name: "bad", tag_filter: ["BAD"]})
      |> json_response(422)

    assert body["error"]["code"] == "tag_invalid"
    assert body["error"]["field"] == "tag_filter"
  end

  test "soft delete excludes from list", %{conn: conn, ws: ws} do
    _ = conn |> post(~p"/api/workspaces/#{ws.slug}/views", %{slug: "v1", name: "v1"})
    _ = conn |> delete(~p"/api/workspaces/#{ws.slug}/views/v1") |> json_response(200)
    idx = conn |> get(~p"/api/workspaces/#{ws.slug}/views") |> json_response(200)
    assert idx["views"] == []
  end

  test "404 on missing view", %{conn: conn, ws: ws} do
    body = conn |> get(~p"/api/workspaces/#{ws.slug}/views/nope") |> json_response(404)
    assert body["error"]["code"] == "not_found"
  end

  test "personal view is hidden from other workspace members", %{conn: conn, ws: ws, user: user} do
    # creator makes a personal view
    _ =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/views", %{slug: "mine", name: "Mine", scope: "personal"})
      |> json_response(201)

    # add a second user to the same workspace with their own token
    other = user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)
    {_t, other_token} = token_fixture(other)

    other_conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{other_token}")

    # other user can't see it in index, can't fetch it, can't modify it
    idx = other_conn |> get(~p"/api/workspaces/#{ws.slug}/views") |> json_response(200)
    refute Enum.any?(idx["views"], &(&1["slug"] == "mine"))

    body = other_conn |> get(~p"/api/workspaces/#{ws.slug}/views/mine") |> json_response(404)
    assert body["error"]["code"] == "not_found"

    # creator still sees it
    own = conn |> get(~p"/api/workspaces/#{ws.slug}/views/mine") |> json_response(200)
    assert own["view"]["slug"] == "mine"
    assert own["view"]["scope"] == "personal"

    _ = user
  end

  test "team view is visible to all members", %{conn: conn, ws: ws} do
    _ =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/views", %{slug: "shared", name: "Shared", scope: "team"})
      |> json_response(201)

    other = user_fixture()
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)
    {_t, other_token} = token_fixture(other)

    other_conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{other_token}")

    show = other_conn |> get(~p"/api/workspaces/#{ws.slug}/views/shared") |> json_response(200)
    assert show["view"]["scope"] == "team"

    # and the non-creator can demote it (no permission gating)
    updated =
      other_conn
      |> patch(~p"/api/workspaces/#{ws.slug}/views/shared", %{scope: "personal"})
      |> json_response(200)

    assert updated["scope"] == "personal"
    # …but now the original creator can't see it (the demoter owns it for visibility purposes)
    # — actually visibility is by created_by_id, so the original creator still sees it.
    own_after = conn |> get(~p"/api/workspaces/#{ws.slug}/views/shared") |> json_response(200)
    assert own_after["view"]["scope"] == "personal"
  end
end
