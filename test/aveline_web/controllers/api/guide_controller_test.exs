defmodule AvelineWeb.Api.GuideControllerTest do
  use AvelineWeb.ConnCase, async: true

  alias Aveline.Fixtures

  test "serves the full guide with its version and changelog" do
    user = Fixtures.user_fixture()
    {_t, token} = Fixtures.token_fixture(user)

    body =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/guide")
      |> json_response(200)

    assert body["guide"]["version"] == Aveline.Guide.version()
    assert body["guide"]["blocks"] == Aveline.Guide.blocks()
    assert [%{"version" => 1, "line" => _} | _] = body["guide"]["changelog"]
  end
end
