defmodule AvelineWeb.Api.StarterControllerTest do
  @moduledoc """
  You should be able to see what Standard contains before choosing it.
  """
  use AvelineWeb.ConnCase, async: true

  alias Aveline.Fixtures

  setup do
    user = Fixtures.user_fixture()
    {_t, token} = Fixtures.token_fixture(user)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")

    {:ok, conn: conn}
  end

  test "standard shows the tags, the boards and the doc it would write", %{conn: conn} do
    body = conn |> get(~p"/api/starter") |> json_response(200)

    assert body["ok"] == true
    assert body["starter"]["setup"] == "standard"
    assert length(body["starter"]["tags"]) == length(Aveline.Workspaces.Template.tags(:standard))

    assert Enum.map(body["starter"]["views"], & &1["name"]) |> Enum.sort() ==
             ["feedback", "ideas", "tickets"]

    headings =
      for %{"type" => "heading", "text" => text} <- body["starter"]["orientation_blocks"],
          do: text

    assert "How we work" in headings
  end

  test "custom shows an empty frame", %{conn: conn} do
    body = conn |> get(~p"/api/starter?setup=custom") |> json_response(200)

    assert body["starter"]["setup"] == "custom"
    assert body["starter"]["tags"] == []
    assert body["starter"]["views"] == []
    assert body["starter"]["docs"] == []
    assert body["starter"]["orientation_blocks"] != []
  end
end
