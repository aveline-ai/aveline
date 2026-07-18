defmodule AvelineWeb.Api.KeyControllerTest do
  @moduledoc """
  API key self-service: list is masked, create shows plaintext exactly
  once, revoke is guarded so the last active key survives, and revoked
  keys stop authenticating.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  setup %{conn: conn} do
    user = user_fixture()
    {token, plaintext} = token_fixture(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext}")
      |> put_req_header("accept", "application/json")

    {:ok, conn: conn, user: user, token: token, plaintext: plaintext}
  end

  test "list shows masked keys, never hashes or plaintext", %{conn: conn, plaintext: plaintext} do
    body = conn |> get(~p"/api/keys") |> json_response(200)

    assert body["ok"] == true
    assert [key] = body["keys"]
    assert key["masked"] =~ "…"
    refute Map.has_key?(key, "token_hash")
    refute String.contains?(Jason.encode!(body), plaintext)
  end

  test "create returns the plaintext once and the key lists after", %{conn: conn} do
    body =
      conn
      |> post(~p"/api/keys", %{"name" => "laptop"})
      |> json_response(200)

    assert body["ok"] == true
    assert String.starts_with?(body["key"], "avl_")
    assert body["name"] == "laptop"
    assert body["masked"] == "avl_…" <> String.slice(body["key"], -4, 4)

    list = conn |> get(~p"/api/keys") |> json_response(200)
    assert length(list["keys"]) == 2
    refute String.contains?(Jason.encode!(list), body["key"])
  end

  test "create requires a name", %{conn: conn} do
    err = conn |> post(~p"/api/keys", %{"name" => "  "}) |> json_response(422)
    assert err["error"]["code"] == "validation_failed"
  end

  test "the last active key can't be revoked; a spare unlocks it", %{conn: conn, token: token} do
    err = conn |> delete(~p"/api/keys/#{token.id}") |> json_response(422)
    assert err["error"]["code"] == "last_key"

    spare = conn |> post(~p"/api/keys", %{"name" => "spare"}) |> json_response(200)

    ok = conn |> delete(~p"/api/keys/#{spare["id"]}") |> json_response(200)
    assert ok["revoked"] == spare["id"]
  end

  test "a revoked key stops authenticating", %{conn: conn, token: token} do
    spare = conn |> post(~p"/api/keys", %{"name" => "spare"}) |> json_response(200)

    # Revoke the key this connection authed with (allowed: a spare remains).
    assert conn |> delete(~p"/api/keys/#{token.id}") |> json_response(200)

    assert conn |> get(~p"/api/me") |> json_response(401)

    fresh =
      build_conn()
      |> put_req_header("authorization", "Bearer #{spare["key"]}")
      |> get(~p"/api/me")
      |> json_response(200)

    assert fresh["ok"] == true
  end

  test "someone else's key id is not_found", %{conn: conn} do
    other = user_fixture()
    {other_token, _} = token_fixture(other)

    err = conn |> delete(~p"/api/keys/#{other_token.id}") |> json_response(404)
    assert err["error"]["code"] == "not_found"

    # And it still works for its owner.
    assert Aveline.Tokens.verify(elem(token_fixture(other), 1))
  end
end
