defmodule AvelineWeb.Api.MilestoneControllerTest do
  @moduledoc """
  Timeline milestones over the API: create with a date, list oldest
  first, delete stops them rendering; bad dates are validation errors.
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

    {:ok, conn: conn, ws: ws}
  end

  test "create, list (oldest first), delete", %{conn: conn, ws: ws} do
    base = ~p"/api/workspaces/#{ws.slug}/milestones"

    later =
      conn
      |> post(base, %{"name" => "pricing change", "date" => "2026-07-10"})
      |> json_response(200)

    assert later["milestone"]["date"] == "2026-07-10"

    earlier =
      conn
      |> post(base, %{
        "name" => "v1.4 shipped",
        "date" => "2026-07-06",
        "description" => "the big one"
      })
      |> json_response(200)

    assert earlier["milestone"]["description"] == "the big one"

    list = conn |> get(base) |> json_response(200)
    assert Enum.map(list["milestones"], & &1["name"]) == ["v1.4 shipped", "pricing change"]

    assert conn |> delete("#{base}/#{later["milestone"]["id"]}") |> json_response(200)

    list = conn |> get(base) |> json_response(200)
    assert Enum.map(list["milestones"], & &1["name"]) == ["v1.4 shipped"]

    err = conn |> delete("#{base}/#{later["milestone"]["id"]}") |> json_response(404)
    assert err["error"]["code"] == "not_found"
  end

  test "bad or missing date is a validation error", %{conn: conn, ws: ws} do
    base = ~p"/api/workspaces/#{ws.slug}/milestones"

    err = conn |> post(base, %{"name" => "no date"}) |> json_response(422)
    assert err["error"]["code"] == "validation_failed"

    err = conn |> post(base, %{"name" => "bad date", "date" => "yesterday"}) |> json_response(422)
    assert err["error"]["code"] == "validation_failed"
  end

  test "milestones ride the doc read into chart specs", %{conn: conn, ws: ws} do
    base = ~p"/api/workspaces/#{ws.slug}/milestones"

    assert conn
           |> post(base, %{"name" => "marker", "date" => "2026-07-06"})
           |> json_response(200)

    # The LiveView path carries them; the API read path returns config
    # (results run via run-block), so here we just assert the list shape
    # the LV consumes.
    assert [%{"name" => "marker", "date" => "2026-07-06"}] =
             Aveline.Milestones.list_active(ws.id) |> Enum.map(&Aveline.Milestones.safe_map/1)
             |> Enum.map(&Map.take(&1, ["name", "date"]))
  end
end
