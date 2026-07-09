defmodule AvelineWeb.Api.ContractControllerTest do
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  test "GET /api/contract requires auth", %{conn: conn} do
    conn = conn |> put_req_header("accept", "application/json") |> get(~p"/api/contract")
    assert json_response(conn, 401)["ok"] == false
  end

  test "GET /api/contract returns the write contract", %{conn: conn} do
    user = user_fixture()
    {_t, plaintext} = token_fixture(user)

    body =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext}")
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/contract")
      |> json_response(200)

    assert body["ok"] == true
    contract = body["contract"]
    assert is_map(contract)
    assert length(contract["block_types"]) == 7
    assert Enum.any?(contract["block_types"], &(&1["type"] == "chart"))
    assert length(contract["operations"]) == 5
    assert contract["edit_modes"]["note"] =~ "exactly one"
  end
end
