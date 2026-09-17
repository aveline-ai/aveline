defmodule AvelineWeb.Api.FeDocsControllerTest do
  @moduledoc """
  The Elm Docs page's read endpoints (/papi …/fe/docs-list and
  …/fe/docs-facets): enriched card fields, has_more pagination, and
  corpus-wide facet counts under the shared filter grammar.

  Workspaces are born seeded (orientation + template docs, starter
  tags), so assertions scope by fresh `fed-*` tags rather than assuming
  an empty corpus.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  alias Aveline.Workspaces

  setup %{conn: conn} do
    user = user_fixture()
    ws = workspace_fixture(user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put_req_header("accept", "application/json")

    {:ok, conn: conn, user: user, ws: ws}
  end

  defp list(conn, ws, params) do
    conn
    |> get(~p"/papi/workspaces/#{ws.slug}/fe/docs-list?#{params}")
    |> json_response(200)
  end

  defp facets(conn, ws, params) do
    conn
    |> get(~p"/papi/workspaces/#{ws.slug}/fe/docs-facets?#{params}")
    |> json_response(200)
  end

  defp tag!(ws, user, slug) do
    {:ok, _} = Aveline.Tags.create(ws.id, slug, "a tag used by the fe-docs tests", user.id)
  end

  test "docs-list carries the card fields the LV rendered", %{conn: conn, ws: ws, user: user} do
    tag!(ws, user, "fed-runbook")
    doc_fixture(ws, user, title: "Private one", tags: ["fed-runbook"], visibility: "private")

    body = list(conn, ws, %{"tag" => "fed-runbook"})

    assert body["ok"] == true
    assert body["has_more"] == false
    assert [doc] = body["docs"]
    assert doc["title"] == "Private one"
    assert doc["visibility"] == "private"
    assert doc["tags"] == ["fed-runbook"]
    assert doc["actor_user"]["username"] == user.username
    assert doc["view_count"] == 0
    assert doc["kudos_count"] == 0
    assert is_binary(doc["base_doc_id"])
  end

  test "has_more pagination via limit/offset", %{conn: conn, ws: ws, user: user} do
    tag!(ws, user, "fed-page")
    for i <- 1..3, do: doc_fixture(ws, user, title: "Doc #{i}", tags: ["fed-page"])

    page1 = list(conn, ws, %{"tag" => "fed-page", "limit" => 2})
    assert length(page1["docs"]) == 2
    assert page1["has_more"] == true

    page2 = list(conn, ws, %{"tag" => "fed-page", "limit" => 2, "offset" => 2})
    assert length(page2["docs"]) == 1
    assert page2["has_more"] == false
  end

  test "flat pages carry the filtered total", %{conn: conn, ws: ws, user: user} do
    tag!(ws, user, "fed-total")
    for i <- 1..3, do: doc_fixture(ws, user, title: "Doc #{i}", tags: ["fed-total"])

    body = list(conn, ws, %{"tag" => "fed-total", "limit" => 2})
    assert length(body["docs"]) == 2
    assert body["total"] == 3
  end

  test "group=<scope> paginates each column independently", %{conn: conn, ws: ws, user: user} do
    tag!(ws, user, "fed-grp")
    tag!(ws, user, "fedst:todo")
    tag!(ws, user, "fedst:done")
    tag!(ws, user, "fedst:empty")
    for i <- 1..3, do: doc_fixture(ws, user, title: "Todo #{i}", tags: ["fed-grp", "fedst:todo"])
    doc_fixture(ws, user, title: "Done 1", tags: ["fed-grp", "fedst:done"])
    doc_fixture(ws, user, title: "Loose 1", tags: ["fed-grp"])

    body = list(conn, ws, %{"tag" => "fed-grp", "group" => "fedst", "limit" => 2})
    assert body["total"] == 5

    # Member order, unassigned last, empty column dropped.
    assert Enum.map(body["groups"], & &1["key"]) == ["fedst:done", "fedst:todo", nil]

    todo = Enum.find(body["groups"], &(&1["key"] == "fedst:todo"))
    assert length(todo["docs"]) == 2
    assert todo["has_more"] == true
    assert todo["total"] == 3

    done = Enum.find(body["groups"], &(&1["key"] == "fedst:done"))
    assert done == %{"key" => "fedst:done", "docs" => done["docs"], "has_more" => false, "total" => 1}
    assert [%{"title" => "Done 1"}] = done["docs"]

    loose = Enum.find(body["groups"], &is_nil(&1["key"]))
    assert [%{"title" => "Loose 1"}] = loose["docs"]

    # Paging one column answers in the flat shape.
    more =
      list(conn, ws, %{
        "tag" => "fed-grp",
        "group" => "fedst",
        "key" => "fedst:todo",
        "limit" => 2,
        "offset" => 2
      })

    assert [%{"title" => "Todo 1"}] = more["docs"]
    assert more["has_more"] == false
    assert more["total"] == 3

    none = list(conn, ws, %{"tag" => "fed-grp", "group" => "fedst", "key" => "none"})
    assert [%{"title" => "Loose 1"}] = none["docs"]
    assert none["total"] == 1
  end

  test "group key outside the scope is rejected", %{conn: conn, ws: ws, user: user} do
    tag!(ws, user, "fedst2:todo")

    body =
      conn
      |> get(~p"/papi/workspaces/#{ws.slug}/fe/docs-list?group=fedst2&key=fedst2:nope")
      |> json_response(422)

    assert body["ok"] == false
  end

  test "filters: tag and q compose", %{conn: conn, ws: ws, user: user} do
    tag!(ws, user, "fed-runbook")
    tag!(ws, user, "fed-spec")
    doc_fixture(ws, user, title: "Deploy fedrunbook", tags: ["fed-runbook"])
    doc_fixture(ws, user, title: "Frobnicator spec", tags: ["fed-spec"])

    tagged = list(conn, ws, %{"tag" => "fed-runbook"})
    assert Enum.map(tagged["docs"], & &1["title"]) == ["Deploy fedrunbook"]

    searched = list(conn, ws, %{"q" => "frobnicator"})
    assert Enum.map(searched["docs"], & &1["title"]) == ["Frobnicator spec"]
  end

  test "author filters by username; unknown usernames are ignored",
       %{conn: conn, ws: ws, user: user} do
    other = user_fixture()
    {:ok, _} = Workspaces.ensure_member(ws.id, other.id)
    doc_fixture(ws, other, title: "Other doc", visibility: "workspace")

    body = list(conn, ws, %{"author" => other.username})
    assert Enum.map(body["docs"], & &1["title"]) == ["Other doc"]

    # Unknown username drops out of the filter instead of erroring —
    # same as the LV, where an unknown author chip can't be selected.
    unfiltered = list(conn, ws, %{})
    ignored = list(conn, ws, %{"author" => "nobody-here"})
    assert Enum.map(ignored["docs"], & &1["title"]) == Enum.map(unfiltered["docs"], & &1["title"])
    assert user.username != other.username
  end

  test "docs-facets counts the whole filtered corpus by tag and author",
       %{conn: conn, ws: ws, user: user} do
    tag!(ws, user, "fed-runbook")
    tag!(ws, user, "fed-spec")
    doc_fixture(ws, user, title: "A", tags: ["fed-runbook"])
    doc_fixture(ws, user, title: "B", tags: ["fed-runbook", "fed-spec"])

    body = facets(conn, ws, %{})

    assert body["ok"] == true
    assert body["tags"]["fed-runbook"] == 2
    assert body["tags"]["fed-spec"] == 1
    assert is_integer(body["authors"][user.username])

    # Under a tag filter the counts shrink to the overlap.
    filtered = facets(conn, ws, %{"tag" => "fed-spec"})
    assert filtered["tags"]["fed-runbook"] == 1
    assert filtered["tags"]["fed-spec"] == 1
    assert filtered["authors"][user.username] == 1
  end

  test "bad sort is rejected with the envelope error", %{conn: conn, ws: ws} do
    body =
      conn
      |> get(~p"/papi/workspaces/#{ws.slug}/fe/docs-list?sort=alphabetical")
      |> json_response(422)

    assert body["ok"] == false
    assert body["error"]["code"] == "list_param_invalid"
  end
end
