defmodule AvelineWeb.Api.TemplateControllerTest do
  @moduledoc """
  You should be able to see what a template contains before choosing it,
  from the CLI with a token and from the signup page without one.
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

  test "lists the three templates with counts", %{conn: conn} do
    body = conn |> get(~p"/api/templates") |> json_response(200)
    assert body["ok"] == true
    assert Enum.map(body["templates"], & &1["name"]) == ["autonomous-dev", "knowledge-base", "blank"]
    assert %{"recommended" => true, "tag_count" => 18, "view_count" => 3, "doc_count" => 1} = hd(body["templates"])
    assert %{"name" => "blank", "tag_count" => 0, "view_count" => 0, "doc_count" => 0} = List.last(body["templates"])
  end

  test "shows everything a template would create, without creating it", %{conn: conn} do
    body = conn |> get(~p"/api/templates/autonomous-dev") |> json_response(200)
    t = body["template"]
    assert t["name"] == "autonomous-dev"
    slugs = Enum.map(t["tags"], & &1["slug"])
    assert "idea" in slugs and "status:in-flight" in slugs
    assert Enum.map(t["views"], & &1["name"]) |> Enum.sort() == ["feedback", "ideas", "tickets"]
    assert for(%{"type" => "heading", "text" => h} <- t["orientation_blocks"], do: h) |> Enum.member?("How we work")
    assert [%{"slug" => "idea-template"}] = t["docs"]

    assert %{"tags" => [], "views" => [], "docs" => []} =
             conn |> get(~p"/api/templates/blank") |> json_response(200) |> Map.fetch!("template")
  end

  test "an unknown template is not found", %{conn: conn} do
    body = conn |> get(~p"/api/templates/autonomous-dve") |> json_response(404)
    assert body["ok"] == false
    assert body["error"]["code"] == "not_found"
  end

  test "the browser twin is open, so the signup picker works before login" do
    conn = build_conn() |> put_req_header("accept", "application/json")
    assert conn |> get("/papi/templates") |> json_response(200) |> Map.fetch!("templates") |> length() == 3
    assert conn |> get("/papi/templates/blank") |> json_response(200) |> get_in(["template", "name"]) == "blank"
    assert conn |> get("/papi/guide") |> json_response(200) |> get_in(["guide", "version"]) == Aveline.Guide.version()
  end

  test "create-workspace requires a template and refuses an unknown one", %{conn: conn} do
    body = conn |> post(~p"/api/workspaces", %{"name" => "No Template"}) |> json_response(422)
    assert body["error"]["code"] == "template_required"

    body = conn |> post(~p"/api/workspaces", %{"name" => "Odd", "template" => "standard"}) |> json_response(422)
    assert body["error"]["code"] == "template_invalid"

    body = conn |> post(~p"/api/workspaces", %{"name" => "Fine", "template" => "blank"}) |> json_response(200)
    assert body["workspace"]["slug"] == "fine"
    assert Aveline.Workspaces.get_by_slug("fine").template == "blank"
  end
end
