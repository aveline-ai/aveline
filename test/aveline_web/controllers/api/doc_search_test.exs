defmodule AvelineWeb.Api.DocSearchTest do
  @moduledoc """
  GET /docs as the single query surface: full-text search (q), author
  filter, sort modes incl. relevance, snippets on search hits, and the
  default/max result limit.
  """
  use AvelineWeb.ConnCase, async: false

  import Aveline.Fixtures

  alias Aveline.Workspaces

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

  defp list(conn, ws, params) do
    conn
    |> get(~p"/api/workspaces/#{ws.slug}/docs?#{params}")
    |> json_response(200)
  end

  defp titles(body), do: Enum.map(body["docs"], & &1["title"])

  test "q filters by full text and hits carry a snippet", %{conn: conn, ws: ws, user: user} do
    doc_fixture(ws, user,
      title: "Deploy runbook",
      blocks: [%{"type" => "paragraph", "content" => [%{"text" => "Roll back with fly deploy"}]}]
    )

    doc_fixture(ws, user, title: "Unrelated", blocks: [
      %{"type" => "paragraph", "content" => [%{"text" => "Nothing to see"}]}
    ])

    body = list(conn, ws, %{"q" => "deploy"})

    assert body["ok"] == true
    assert titles(body) == ["Deploy runbook"]
    assert [%{"snippet" => snippet}] = body["docs"]
    assert snippet =~ "**"
    assert snippet =~ ~r/deploy/i
  end

  test "docs returned without q carry no snippet key", %{conn: conn, ws: ws, user: user} do
    doc_fixture(ws, user, title: "Plain doc")

    body = list(conn, ws, %{})
    refute Map.has_key?(hd(body["docs"]), "snippet")
  end

  test "with q, default order is relevance; sort=recent overrides", %{conn: conn, ws: ws, user: user} do
    # "engine" once, but edited later (recency winner).
    doc_fixture(ws, user,
      title: "Side note",
      blocks: [%{"type" => "paragraph", "content" => [%{"text" => "mentions the engine once"}]}]
    )

    # "engine" everywhere (relevance winner), created first.
    dense =
      doc_fixture(ws, user,
        title: "Engine engine engine",
        summary: "All about the engine",
        blocks: [%{"type" => "paragraph", "content" => [%{"text" => "engine engine engine"}]}]
      )

    # Bump the sparse doc so it is the most recently updated.
    sparse_again =
      doc_fixture(ws, user,
        title: "Engine addendum",
        blocks: [%{"type" => "paragraph", "content" => [%{"text" => "one more engine remark"}]}]
      )

    relevance = list(conn, ws, %{"q" => "engine"})
    assert hd(titles(relevance)) == dense.title

    recent = list(conn, ws, %{"q" => "engine", "sort" => "recent"})
    assert hd(titles(recent)) == sparse_again.title
  end

  test "websearch grammar: -word excludes", %{conn: conn, ws: ws, user: user} do
    doc_fixture(ws, user,
      title: "Postgres tuning",
      blocks: [%{"type" => "paragraph", "content" => [%{"text" => "vacuum and indexes"}]}]
    )

    doc_fixture(ws, user,
      title: "Postgres backups",
      blocks: [%{"type" => "paragraph", "content" => [%{"text" => "wal archiving"}]}]
    )

    body = list(conn, ws, %{"q" => "postgres -backups"})
    assert titles(body) == ["Postgres tuning"]
  end

  test "author filters to that member's docs; unknown author is 422", %{conn: conn, ws: ws, user: user} do
    other = user_fixture()
    {:ok, _} = Workspaces.add_member(ws.id, other.id)
    doc_fixture(ws, user, title: "Mine")
    doc_fixture(ws, other, title: "Theirs")

    body = list(conn, ws, %{"author" => other.username})
    assert titles(body) == ["Theirs"]

    err =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/docs?#{%{"author" => "nobody-here"}}")
      |> json_response(422)

    assert err["error"]["code"] == "unknown_authors"
    assert err["error"]["details"]["unknown_authors"] == ["nobody-here"]
  end

  test "limit defaults to 25 and caps at 100; offset pages", %{conn: conn, ws: ws, user: user} do
    for i <- 1..27, do: doc_fixture(ws, user, title: "Doc #{i}")

    # The workspace comes pre-seeded (orientation doc etc.), so page math
    # is relative to the actual corpus size.
    total = length(list(conn, ws, %{"limit" => "100"})["docs"])
    assert total >= 27

    assert length(list(conn, ws, %{})["docs"]) == 25
    assert length(list(conn, ws, %{"limit" => "5"})["docs"]) == 5

    page2 = list(conn, ws, %{"limit" => "25", "offset" => "25"})
    assert length(page2["docs"]) == total - 25

    err =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/docs?#{%{"limit" => "101"}}")
      |> json_response(422)

    assert err["error"]["code"] == "list_param_invalid"
  end

  test "bad sort is 422 list_param_invalid", %{conn: conn, ws: ws} do
    err =
      conn
      |> get(~p"/api/workspaces/#{ws.slug}/docs?#{%{"sort" => "bogus"}}")
      |> json_response(422)

    assert err["error"]["code"] == "list_param_invalid"
    assert err["error"]["message"] =~ "sort"
  end
end
