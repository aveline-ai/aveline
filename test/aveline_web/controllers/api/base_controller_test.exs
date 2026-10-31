defmodule AvelineWeb.Api.BaseControllerTest do
  @moduledoc """
  The base doc has to be readable before anyone has a token, because it
  is what explains how to get one.
  """
  use AvelineWeb.ConnCase, async: true

  test "GET /api/base needs no token", %{conn: conn} do
    body = conn |> get(~p"/api/base") |> json_response(200)

    assert body["ok"] == true
    assert body["base"]["version"] == Aveline.Primer.version()
    assert is_list(body["base"]["blocks"]) and body["base"]["blocks"] != []
    assert is_list(body["base"]["changelog"]) and body["base"]["changelog"] != []
  end
end
