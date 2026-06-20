defmodule AvelineWeb.Api.DocLifecycleTest do
  @moduledoc """
  Exercise the doc lifecycle end-to-end through the API. Verifies
  the canonical envelope shape, that minimal creates echo `slug` +
  `doc_id` + `version_id` + `version_number`, and that apply_ops
  returns the new version pointer.
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
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user, ws: ws}
  end

  test "create-doc -> get-doc -> apply-ops -> delete", %{conn: conn, ws: ws} do
    {:ok, _tag} = Aveline.Tags.create(ws.id, "stack", "Tech stack notes.", nil)

    create_body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs", %{
        "title" => "Deploy guide",
        "tags" => ["stack"],
        "blocks" => [
          %{"type" => "paragraph", "content" => [%{"text" => "Hi"}]}
        ],
        "intent" => "initial"
      })
      |> json_response(200)

    assert create_body["ok"] == true
    assert create_body["slug"] == "deploy-guide"
    assert is_binary(create_body["doc_id"])
    assert is_binary(create_body["version_id"])
    assert create_body["version_number"] == 1

    get_body =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/docs/deploy-guide")
      |> json_response(200)

    assert get_body["ok"] == true
    assert get_body["doc"]["slug"] == "deploy-guide"
    assert length(get_body["doc"]["blocks"]) == 1

    block_id = get_in(get_body, ["doc", "blocks", Access.at(0), "id"])
    assert is_binary(block_id)

    apply_body =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/docs/deploy-guide", %{
        "intent" => "Add second block",
        "operations" => [
          %{
            "op" => "append_block",
            "block" => %{"type" => "paragraph", "content" => [%{"text" => "More"}]}
          }
        ]
      })
      |> json_response(200)

    assert apply_body["ok"] == true
    assert apply_body["version_number"] == 2

    del_body =
      conn |> delete(~p"/api/workspaces/#{ws.slug}/docs/deploy-guide") |> json_response(200)

    assert del_body["ok"] == true
  end

  test "create-doc without a defined tag returns unknown_tags", %{conn: conn, ws: ws} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/docs", %{
        "title" => "Ghost",
        "tags" => ["does-not-exist"],
        "blocks" => []
      })
      |> json_response(422)

    assert body["ok"] == false
    assert body["error"]["code"] == "unknown_tags"
    assert body["error"]["details"]["unknown_tags"] == ["does-not-exist"]
  end
end
