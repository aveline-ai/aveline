defmodule AvelineWeb.Api.FeAuthApiTest do
  @moduledoc """
  Covers the fe-auth /papi endpoints backing the Elm auth pages:
  signup preview-token / username-status / create, and invite show /
  accept. The :papi pipeline runs protect_from_forgery, so every conn
  carries a CSRF header tied to its test session.
  """
  use AvelineWeb.ConnCase, async: true

  import Aveline.Fixtures

  alias Aveline.Accounts
  alias Aveline.Workspaces

  defp papi_conn(conn, session \\ %{}) do
    csrf = Plug.CSRFProtection.get_csrf_token()
    state = Plug.CSRFProtection.dump_state()

    conn
    |> Plug.Test.init_test_session(Map.merge(%{"_csrf_token" => state}, session))
    |> put_req_header("x-csrf-token", csrf)
  end

  # ===== signup =====

  test "preview-token returns a fresh avl_ token", %{conn: conn} do
    body = conn |> papi_conn() |> get("/papi/signup/preview-token") |> json_response(200)
    assert body["ok"] == true
    assert String.starts_with?(body["token"], "avl_")
  end

  test "username-status reports taken and free", %{conn: conn} do
    user = user_fixture()

    body =
      conn
      |> papi_conn()
      |> get("/papi/signup/username-status?username=#{user.username}")
      |> json_response(200)

    assert body["taken"] == true

    body =
      conn
      |> papi_conn()
      |> get("/papi/signup/username-status?username=definitely-free-#{unique_int()}")
      |> json_response(200)

    assert body["taken"] == false
  end

  test "signup happy path creates user + workspace and returns the preview token", %{conn: conn} do
    token_body = conn |> papi_conn() |> get("/papi/signup/preview-token") |> json_response(200)
    preview = token_body["token"]
    username = "fe-auth-#{unique_int()}"

    body =
      conn
      |> papi_conn()
      |> post("/papi/signup", %{
        "username" => username,
        "workspace_name" => "FE Auth Test #{unique_int()}",
        "token" => preview,
        "copied" => true
      })
      |> json_response(200)

    assert body["ok"] == true
    assert body["user"]["username"] == username
    assert body["token"] == preview
    slug = body["workspace"]["slug"]
    assert is_binary(slug) and slug != ""

    # The token the form showed is the credential: it logs in.
    session_body =
      conn
      |> papi_conn()
      |> post("/papi/session", %{"token" => preview})
      |> json_response(200)

    assert session_body["user"]["username"] == username
  end

  test "signup validation order: username, then workspace, then copy gate", %{conn: conn} do
    taken = user_fixture()

    assert %{"error" => %{"message" => "Username taken."}} =
             conn
             |> papi_conn()
             |> post("/papi/signup", %{
               "username" => taken.username,
               "workspace_name" => "",
               "copied" => false
             })
             |> json_response(422)

    assert %{"error" => %{"message" => "Username too short (min 2)."}} =
             conn
             |> papi_conn()
             |> post("/papi/signup", %{"username" => "a", "workspace_name" => "X", "copied" => true})
             |> json_response(422)

    assert %{"error" => %{"message" => "Pick a workspace name."}} =
             conn
             |> papi_conn()
             |> post("/papi/signup", %{
               "username" => "ok-name-#{unique_int()}",
               "workspace_name" => "",
               "copied" => false
             })
             |> json_response(422)

    assert %{"error" => %{"message" => "Copy the API key first." <> _}} =
             conn
             |> papi_conn()
             |> post("/papi/signup", %{
               "username" => "ok-name-#{unique_int()}",
               "workspace_name" => "Fine Name",
               "copied" => false
             })
             |> json_response(422)
  end

  # ===== invites =====

  test "invite show resolves workspace and membership; 404 on bad code", %{conn: conn} do
    creator = user_fixture()
    ws = workspace_fixture(creator)
    {:ok, invite} = Workspaces.ensure_invite(ws.id, creator.id)

    body = conn |> papi_conn() |> get("/papi/invites/#{invite.code}") |> json_response(200)
    assert body["workspace"]["slug"] == ws.slug
    assert body["already_member"] == false

    body =
      conn
      |> papi_conn(%{"user_id" => creator.id})
      |> get("/papi/invites/#{invite.code}")
      |> json_response(200)

    assert body["already_member"] == true

    body = conn |> papi_conn() |> get("/papi/invites/nope") |> json_response(404)
    assert body["error"]["code"] == "not_found"
  end

  test "invite accept joins the signed-in user", %{conn: conn} do
    creator = user_fixture()
    ws = workspace_fixture(creator)
    {:ok, invite} = Workspaces.ensure_invite(ws.id, creator.id)
    joiner = user_fixture()

    body =
      conn
      |> papi_conn(%{"user_id" => joiner.id})
      |> post("/papi/invites/#{invite.code}/accept")
      |> json_response(200)

    assert body["workspace"]["slug"] == ws.slug
    assert Workspaces.member?(ws.id, joiner.id)

    # Signed-out accept is rejected by the auth plug.
    body = conn |> papi_conn() |> post("/papi/invites/#{invite.code}/accept") |> json_response(401)
    assert body["error"]["code"] == "unauthorized"
  end

  test "signup via invite joins that workspace instead of creating one", %{conn: conn} do
    creator = user_fixture()
    ws = workspace_fixture(creator)
    {:ok, invite} = Workspaces.ensure_invite(ws.id, creator.id)
    username = "invitee-#{unique_int()}"

    body =
      conn
      |> papi_conn()
      |> post("/papi/signup", %{
        "username" => username,
        "invite_code" => invite.code,
        "copied" => true
      })
      |> json_response(200)

    assert body["workspace"]["slug"] == ws.slug
    assert String.starts_with?(body["token"], "avl_")

    user = Accounts.get_user_by_username(username)
    assert Workspaces.member?(ws.id, user.id)

    # Invite wording for username errors on the invite path.
    assert %{"error" => %{"message" => "Too short (minimum 2 characters)."}} =
             conn
             |> papi_conn()
             |> post("/papi/signup", %{"username" => "a", "invite_code" => invite.code, "copied" => true})
             |> json_response(422)

    # Dead invite code 404s instead of minting an orphan account.
    assert %{"error" => %{"code" => "not_found"}} =
             conn
             |> papi_conn()
             |> post("/papi/signup", %{
               "username" => "someone-#{unique_int()}",
               "invite_code" => "nope",
               "copied" => true
             })
             |> json_response(404)
  end
end
