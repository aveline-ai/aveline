defmodule AvelineWeb.Api.TagControllerTest do
  @moduledoc """
  Tag lifecycle over HTTP — integration coverage for the Gleam handlers
  (src/aveline/handlers/tags.gleam) + CtxBuilder boundary. Behavior must
  match the pre-Gleam endpoints exactly (envelopes, codes, events).
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  alias Aveline.Docs
  alias Aveline.Tags

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)
    {_t, token} = token_fixture(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, ws: ws, user: user}
  end

  # ===== create =====

  test "create returns the tag and records tag_created", %{conn: conn, ws: ws, user: user} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/tags", %{
        "slug" => "  Deploys ",
        "description" => " Shipping things. ",
        "color" => "#123ABC"
      })
      |> json_response(200)

    assert body["tag"]["slug"] == "deploys"
    assert body["tag"]["description"] == "Shipping things."
    assert body["tag"]["color"] == "#123abc"
    assert body["tag"]["version_number"] == 1
    assert is_binary(body["tag"]["created_at"])

    events = conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)

    assert Enum.any?(events["events"], fn e ->
             e["action"] == "tag_created" and e["target_label"] == "deploys" and
               get_in(e, ["actor", "user", "username"]) == user.username
           end)
  end

  test "create accepts `name` as a slug alias", %{conn: conn, ws: ws} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/tags", %{
        "name" => "field-guides",
        "description" => "How-to guides."
      })
      |> json_response(200)

    assert body["tag"]["slug"] == "field-guides"
  end

  # Legacy quirk kept for parity: the composite unique index reports on
  # :workspace_id, so a duplicate CREATE fell through the changeset
  # summary as plain validation_failed — only rename/restore collisions
  # say slug_taken.
  test "create duplicate slug is validation_failed", %{conn: conn, ws: ws, user: user} do
    {:ok, _} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)

    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/tags", %{
        "slug" => "deploys",
        "description" => "Another description."
      })
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
  end

  test "create malformed slug is tag_invalid", %{conn: conn, ws: ws} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/tags", %{
        "slug" => "bad slug",
        "description" => "Shipping things."
      })
      |> json_response(422)

    assert body["error"]["code"] == "tag_invalid"
  end

  test "create short description is validation_failed", %{conn: conn, ws: ws} do
    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/tags", %{"slug" => "deploys", "description" => "meh"})
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
  end

  test "create scoped slug works; broken scoped slug does not", %{conn: conn, ws: ws} do
    assert conn
           |> post(~p"/api/workspaces/#{ws.slug}/tags", %{
             "slug" => "team:growth",
             "description" => "Owned by the growth team."
           })
           |> json_response(200)

    body =
      conn
      |> post(~p"/api/workspaces/#{ws.slug}/tags", %{
        "slug" => "a:b:c",
        "description" => "Too many colons."
      })
      |> json_response(422)

    assert body["error"]["code"] == "tag_invalid"
  end

  # ===== index / show =====

  test "index lists tags with stats in tag order", %{conn: conn, ws: ws, user: user} do
    # The workspace fixture seeds a default taxonomy, so assert relative
    # order + stats rather than the whole list. "zz-late"'s sort_key
    # overrides its slug, so it sorts before "aa-early" despite the name.
    {:ok, _} = Tags.create(ws.id, "aa-early", "Alphabetically first tag.", user.id)
    {:ok, _} = Tags.create(ws.id, "zz-late", "Sort-key overridden tag.", user.id, sort_key: "aa-e")
    doc_fixture(ws, user, title: "Uses aa-early", tags: ["aa-early"])

    body = conn |> get(~p"/api/workspaces/#{ws.slug}/tags") |> json_response(200)
    slugs = Enum.map(body["tags"], & &1["slug"])

    late_at = Enum.find_index(slugs, &(&1 == "zz-late"))
    early_at = Enum.find_index(slugs, &(&1 == "aa-early"))
    assert late_at != nil and early_at != nil
    assert late_at < early_at

    early = Enum.find(body["tags"], &(&1["slug"] == "aa-early"))
    assert early["doc_count"] == 1
    assert is_binary(early["last_used_at"])

    late = Enum.find(body["tags"], &(&1["slug"] == "zz-late"))
    assert late["doc_count"] == 0
    assert late["last_used_at"] == nil
    assert late["sort_key"] == "aa-e"
  end

  test "show returns the tag; unknown slug is 404", %{conn: conn, ws: ws, user: user} do
    {:ok, _} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)

    body = conn |> get(~p"/api/workspaces/#{ws.slug}/tags/deploys") |> json_response(200)
    assert body["tag"]["slug"] == "deploys"

    body = conn |> get(~p"/api/workspaces/#{ws.slug}/tags/nope") |> json_response(404)
    assert body["error"]["code"] == "not_found"
  end

  # ===== update =====

  test "update description versions the tag and records tag_updated", %{conn: conn, ws: ws, user: user} do
    {:ok, _} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)

    body =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/tags/deploys", %{"description" => "Now clearer."})
      |> json_response(200)

    assert body["tag"]["description"] == "Now clearer."
    assert body["tag"]["version_number"] == 2

    events = conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)
    assert Enum.any?(events["events"], &(&1["action"] == "tag_updated"))
  end

  test "rename cascades across docs and records tag_renamed", %{conn: conn, ws: ws, user: user} do
    {:ok, _} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)
    doc = doc_fixture(ws, user, title: "Uses it", tags: ["deploys"])

    body =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/tags/deploys", %{"new_slug" => "shipping"})
      |> json_response(200)

    assert body["tag"]["slug"] == "shipping"
    assert body["tag"]["version_number"] == 2

    assert Docs.get_current_by_slug(ws.id, doc.slug).tags == ["shipping"]
    assert Tags.get(ws.id, "deploys") == nil

    events = conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)
    assert Enum.any?(events["events"], &(&1["action"] == "tag_renamed"))
  end

  test "rename into an occupied slug is slug_taken", %{conn: conn, ws: ws, user: user} do
    {:ok, _} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)
    {:ok, _} = Tags.create(ws.id, "shipping", "Other tag entirely.", user.id)

    body =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/tags/deploys", %{"new_slug" => "shipping"})
      |> json_response(422)

    assert body["error"]["code"] == "slug_taken"
    assert body["error"]["details"]["field"] == "slug"
  end

  test "no-op update returns the current version untouched", %{conn: conn, ws: ws, user: user} do
    {:ok, _} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)

    body =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/tags/deploys", %{"description" => "Shipping things."})
      |> json_response(200)

    assert body["tag"]["version_number"] == 1
  end

  test "empty string clears color; bad color is validation_failed", %{conn: conn, ws: ws, user: user} do
    {:ok, tag} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)
    {:ok, _} = Tags.edit(tag, %{color: "#123abc"}, user.id)

    body =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/tags/deploys", %{"color" => ""})
      |> json_response(200)

    assert body["tag"]["color"] == nil
    assert body["tag"]["version_number"] == 3

    body =
      conn
      |> patch(~p"/api/workspaces/#{ws.slug}/tags/deploys", %{"color" => "green"})
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
  end

  test "update unknown tag is 404", %{conn: conn, ws: ws} do
    assert conn
           |> patch(~p"/api/workspaces/#{ws.slug}/tags/nope", %{"description" => "Whatever here."})
           |> json_response(404)
  end

  # ===== delete / restore =====

  test "delete hides the tag, restore brings it back, events recorded", %{conn: conn, ws: ws, user: user} do
    {:ok, _} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)
    doc = doc_fixture(ws, user, title: "Tagged", tags: ["deploys"])

    assert conn |> delete(~p"/api/workspaces/#{ws.slug}/tags/deploys") |> json_response(200)
    assert conn |> get(~p"/api/workspaces/#{ws.slug}/tags/deploys") |> json_response(404)

    # Docs keep the slug in their rows — restore is a perfect inverse.
    body = conn |> post(~p"/api/workspaces/#{ws.slug}/tags/deploys/restore") |> json_response(200)
    assert body["tag"]["slug"] == "deploys"

    assert conn |> get(~p"/api/workspaces/#{ws.slug}/tags/deploys") |> json_response(200)
    assert Docs.get_current_by_slug(ws.id, doc.slug).tags == ["deploys"]

    events = conn |> get(~p"/api/workspaces/#{ws.slug}/events") |> json_response(200)
    actions = Enum.map(events["events"], & &1["action"])
    assert "tag_deleted" in actions
    assert "tag_restored" in actions
  end

  test "delete unknown tag is 404; restore without a deleted row is 404", %{conn: conn, ws: ws} do
    assert conn |> delete(~p"/api/workspaces/#{ws.slug}/tags/nope") |> json_response(404)
    assert conn |> post(~p"/api/workspaces/#{ws.slug}/tags/nope/restore") |> json_response(404)
  end

  test "restore is slug_taken when a live tag reclaimed the slug", %{conn: conn, ws: ws, user: user} do
    {:ok, tag} = Tags.create(ws.id, "deploys", "Shipping things.", user.id)
    {:ok, _} = Tags.delete(tag, user.id)
    {:ok, _} = Tags.create(ws.id, "deploys", "A reborn deploys tag.", user.id)

    body = conn |> post(~p"/api/workspaces/#{ws.slug}/tags/deploys/restore") |> json_response(422)
    assert body["error"]["code"] == "slug_taken"
  end
end
