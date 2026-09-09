defmodule AvelineWeb.Api.TeamApiTest do
  @moduledoc """
  Team endpoints over HTTP — integration coverage for the Gleam handler
  (src/aveline/handlers/team.gleam) + CtxBuilder boundary. Behavior
  must match the pre-Gleam endpoints exactly (codes, envelopes, events,
  PubSub broadcasts).
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  alias Aveline.Workspaces

  setup %{conn: conn} do
    owner = user_fixture()
    other = user_fixture()
    ws = workspace_fixture(owner)

    {_t, token} = token_fixture(owner)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, ws: ws, owner: owner, other: other}
  end

  describe "GET /members" do
    test "lists members with user info, role and joined_at", %{conn: conn, ws: ws, owner: owner} do
      body = conn |> get(~p"/api/workspaces/#{ws.slug}/members") |> json_response(200)

      assert body["ok"] == true
      assert [m] = body["members"]
      assert m["id"] == owner.id
      assert m["username"] == owner.username
      assert m["display_name"] == owner.display_name
      assert m["email"] == owner.email
      assert m["role"] == "member"
      assert {:ok, _, _} = DateTime.from_iso8601(m["joined_at"])
    end
  end

  describe "POST /members" do
    test "adds a user by username, records an event, broadcasts", %{conn: conn, ws: ws, other: other} do
      Phoenix.PubSub.subscribe(Aveline.PubSub, Workspaces.members_topic(ws.id))

      body =
        conn
        |> post(~p"/api/workspaces/#{ws.slug}/members", %{"username" => other.username})
        |> json_response(200)

      assert body == %{"ok" => true}
      assert Workspaces.member?(ws.id, other.id)
      assert_receive {:member_added, %{user: %{id: added_id}}}
      assert added_id == other.id

      events = conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)

      assert Enum.any?(events["events"], fn e ->
               e["action"] == "member_joined" and e["target_id"] == other.id and
                 e["target_label"] == other.username
             end)
    end

    test "normalizes the username (trim + downcase)", %{conn: conn, ws: ws, other: other} do
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/members", %{
        "username" => "  #{String.upcase(other.username)} "
      })
      |> json_response(200)

      assert Workspaces.member?(ws.id, other.id)
    end

    test "unknown username is 404", %{conn: conn, ws: ws} do
      body =
        conn
        |> post(~p"/api/workspaces/#{ws.slug}/members", %{"username" => "nobody-here"})
        |> json_response(404)

      assert body["error"]["code"] == "not_found"
    end

    test "adding an existing member is already_member", %{conn: conn, ws: ws, owner: owner} do
      body =
        conn
        |> post(~p"/api/workspaces/#{ws.slug}/members", %{"username" => owner.username})
        |> json_response(422)

      assert body["error"]["code"] == "already_member"
    end
  end

  describe "DELETE /members/:user_id" do
    setup %{ws: ws, other: other} do
      {:ok, _} = Workspaces.ensure_member(ws.id, other.id)
      :ok
    end

    test "removes by user id, records an event, broadcasts", %{conn: conn, ws: ws, other: other} do
      Phoenix.PubSub.subscribe(Aveline.PubSub, Workspaces.members_topic(ws.id))

      body =
        conn |> delete(~p"/api/workspaces/#{ws.slug}/members/#{other.id}") |> json_response(200)

      assert body == %{"ok" => true}
      refute Workspaces.member?(ws.id, other.id)
      assert_receive {:member_removed, %{user_id: removed_id}}
      assert removed_id == other.id

      events = conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)

      assert Enum.any?(events["events"], fn e ->
               e["action"] == "member_removed" and e["target_id"] == other.id and
                 e["target_label"] == other.username
             end)
    end

    test "removes by username", %{conn: conn, ws: ws, other: other} do
      conn
      |> delete(~p"/api/workspaces/#{ws.slug}/members/#{other.username}")
      |> json_response(200)

      refute Workspaces.member?(ws.id, other.id)
    end

    test "self-remove is rejected", %{conn: conn, ws: ws, owner: owner} do
      body =
        conn |> delete(~p"/api/workspaces/#{ws.slug}/members/#{owner.id}") |> json_response(422)

      assert body["error"]["code"] == "self_remove"
      assert Workspaces.member?(ws.id, owner.id)
    end

    test "unknown username is not_member", %{conn: conn, ws: ws} do
      body =
        conn |> delete(~p"/api/workspaces/#{ws.slug}/members/nobody-here") |> json_response(422)

      assert body["error"]["code"] == "not_member"
    end

    test "a user id with no membership is not_member", %{conn: conn, ws: ws} do
      stranger = user_fixture()

      body =
        conn
        |> delete(~p"/api/workspaces/#{ws.slug}/members/#{stranger.id}")
        |> json_response(422)

      assert body["error"]["code"] == "not_member"
    end
  end

  describe "POST /invite + DELETE /invite" do
    test "mints an invite and is idempotent", %{conn: conn, ws: ws} do
      body = conn |> post(~p"/api/workspaces/#{ws.slug}/invite") |> json_response(200)

      assert "inv_" <> _ = body["code"]
      assert String.ends_with?(body["url"], "/invite/" <> body["code"])

      again = conn |> post(~p"/api/workspaces/#{ws.slug}/invite") |> json_response(200)
      assert again["code"] == body["code"]
    end

    test "revoke deactivates; the next mint is fresh", %{conn: conn, ws: ws, owner: owner} do
      first = conn |> post(~p"/api/workspaces/#{ws.slug}/invite") |> json_response(200)

      assert conn |> delete(~p"/api/workspaces/#{ws.slug}/invite") |> json_response(200) ==
               %{"ok" => true}

      assert Workspaces.get_active_invite_for_workspace(ws.id) == nil

      revoked = Aveline.Repo.get_by(Aveline.Workspaces.Invite, code: first["code"])
      assert revoked.revoked_at
      assert revoked.revoked_by_id == owner.id

      fresh = conn |> post(~p"/api/workspaces/#{ws.slug}/invite") |> json_response(200)
      assert fresh["code"] != first["code"]
    end

    test "revoke with no active invite is a quiet success", %{conn: conn, ws: ws} do
      assert conn |> delete(~p"/api/workspaces/#{ws.slug}/invite") |> json_response(200) ==
               %{"ok" => true}
    end
  end
end
