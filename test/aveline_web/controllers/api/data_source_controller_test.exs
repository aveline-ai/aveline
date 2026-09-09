defmodule AvelineWeb.Api.DataSourceControllerTest do
  @moduledoc """
  Data sources over HTTP — integration coverage for the Gleam handler
  (src/aveline/handlers/data_sources.gleam) + CtxBuilder boundary.
  Behavior must match the pre-Gleam endpoint exactly. Query execution
  against real hosts is covered in test/aveline/data_sources_test.exs.
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

  defp create!(conn, ws, attrs) do
    post(conn, ~p"/api/workspaces/#{ws.slug}/data-sources", attrs)
  end

  test "index lists the built-in source with its flags", %{conn: conn, ws: ws} do
    body = conn |> get(~p"/api/workspaces/#{ws.slug}/data-sources") |> json_response(200)

    assert body["ok"] == true
    assert [derived] = body["data_sources"]
    assert derived["name"] == "derived"
    assert derived["adapter"] == "workspace"
    assert derived["built_in"] == true
    assert derived["credential"] == "none"
    assert derived["deleted"] == false
  end

  test "create validates, normalizes the name, and echoes the safe map", %{conn: conn, ws: ws} do
    body =
      conn
      |> create!(ws, %{
        "name" => "  PROD ",
        "url" => "postgres://metrics_ro:<password>@db.example.com:5432/prod",
        "password" => "hunter2"
      })
      |> json_response(200)

    ds = body["data_source"]
    assert ds["name"] == "prod"
    assert ds["adapter"] == "postgres"
    assert ds["url"] == "postgres://metrics_ro:<password>@db.example.com:5432/prod"
    assert ds["credential"] == "live"
    refute Map.has_key?(ds, "built_in")
    refute inspect(body) =~ "hunter2"
  end

  test "create error paths keep their codes", %{conn: conn, ws: ws} do
    err =
      conn
      |> create!(ws, %{"name" => "derived", "url" => "x", "password" => "p"})
      |> json_response(422)

    assert err["error"]["code"] == "reserved_name"

    err =
      conn
      |> create!(ws, %{"name" => "prod", "url" => "postgres://u:<password>@h/db"})
      |> json_response(422)

    assert err["error"]["code"] == "invalid_data_source_url"
    assert err["error"]["message"] =~ "password is required"

    err =
      conn
      |> create!(ws, %{"name" => "prod", "url" => "http://u:<password>@h/db", "password" => "p"})
      |> json_response(422)

    assert err["error"]["code"] == "invalid_data_source_url"
    assert err["error"]["message"] =~ "unsupported scheme"

    err =
      conn
      |> create!(ws, %{"name" => "Bad Name", "url" => "postgres://u:<password>@h/db", "password" => "p"})
      |> json_response(422)

    assert err["error"]["code"] == "validation_failed"
  end

  test "update: rename alone works; template change without password is refused", %{conn: conn, ws: ws} do
    assert conn
           |> create!(ws, %{"name" => "prod", "url" => "postgres://u:<password>@h/db", "password" => "p"})
           |> json_response(200)

    err =
      conn
      |> put(~p"/api/workspaces/#{ws.slug}/data-sources/prod", %{
        "url" => "postgres://u:<password>@evil.example.com/db"
      })
      |> json_response(422)

    assert err["error"]["code"] == "password_required"

    body =
      conn
      |> put(~p"/api/workspaces/#{ws.slug}/data-sources/prod", %{"new_name" => "analytics"})
      |> json_response(200)

    assert body["data_source"]["name"] == "analytics"
    assert body["data_source"]["version_number"] == 2
    assert body["data_source"]["credential"] == "live"

    assert conn
           |> put(~p"/api/workspaces/#{ws.slug}/data-sources/ghost", %{"new_name" => "x"})
           |> json_response(404)
  end

  test "the built-in source is immutable", %{conn: conn, ws: ws} do
    err =
      conn
      |> put(~p"/api/workspaces/#{ws.slug}/data-sources/derived", %{"new_name" => "x"})
      |> json_response(422)

    assert err["error"]["code"] == "workspace_source_immutable"

    err =
      conn
      |> delete(~p"/api/workspaces/#{ws.slug}/data-sources/derived")
      |> json_response(422)

    assert err["error"]["code"] == "workspace_source_immutable"
  end

  test "query requires SQL and a real source", %{conn: conn, ws: ws} do
    err =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/data-sources/derived/query", %{"query" => "  "})
      |> json_response(422)

    assert err["error"]["code"] == "validation_failed"
    assert err["error"]["message"] == "query is required"

    assert conn
           |> post(~p"/api/workspaces/#{ws.slug}/data-sources/ghost/query", %{"query" => "select 1"})
           |> json_response(404)
  end

  test "unreachable sources return query_failed, not a crash", %{conn: conn, ws: ws} do
    assert conn
           |> create!(ws, %{
             "name" => "refused",
             "url" => "postgres://u:<password>@localhost:1/db",
             "password" => "p"
           })
           |> json_response(200)

    err =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/data-sources/refused/query", %{"query" => "select 1"})
      |> json_response(422)

    assert err["error"]["code"] == "query_failed"
  end

  test "delete soft-deletes and the source stops listing", %{conn: conn, ws: ws} do
    assert conn
           |> create!(ws, %{"name" => "prod", "url" => "postgres://u:<password>@h/db", "password" => "p"})
           |> json_response(200)

    assert conn
           |> delete(~p"/api/workspaces/#{ws.slug}/data-sources/prod")
           |> json_response(200)

    body = conn |> get(~p"/api/workspaces/#{ws.slug}/data-sources") |> json_response(200)
    refute Enum.any?(body["data_sources"], &(&1["name"] == "prod"))

    assert conn
           |> delete(~p"/api/workspaces/#{ws.slug}/data-sources/prod")
           |> json_response(404)
  end
end
