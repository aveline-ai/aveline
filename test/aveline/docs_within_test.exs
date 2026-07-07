defmodule Aveline.DocsWithinTest do
  use Aveline.DataCase, async: false

  import Ecto.Query
  alias Aveline.{Docs, Fixtures, Repo}
  alias Aveline.Docs.Doc

  setup do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)

    old = Fixtures.doc_fixture(ws, user, slug: "old-doc", title: "Old")
    _new = Fixtures.doc_fixture(ws, user, slug: "new-doc", title: "New")

    # Backdate the OLD doc's v1 creation to 40 days ago.
    long_ago = DateTime.add(DateTime.utc_now(), -40 * 24 * 3600, :second)

    Repo.update_all(
      from(d in Doc, where: d.base_doc_id == ^old.base_doc_id and d.version_number == 1),
      set: [inserted_at: long_ago]
    )

    # Edit the OLD doc NOW: current version is recent, creation is not.
    {:ok, _} =
      Docs.apply_ops(
        Docs.get_current_by_slug(ws.id, "old-doc"),
        [%{"op" => "append_block", "block" => %{"type" => "paragraph", "content" => [%{"text" => "e"}]}}],
        %{actor_user_id: user.id, actor_type: "agent"},
        dispositions: []
      )

    %{ws: ws}
  end

  @mine ["old-doc", "new-doc"]
  defp slugs(ws, opts) do
    ws.id |> Docs.list_current(opts) |> Enum.map(& &1.slug) |> Enum.filter(&(&1 in @mine)) |> Enum.sort()
  end

  defp ordered(ws, opts) do
    ws.id |> Docs.list_current(opts) |> Enum.map(& &1.slug) |> Enum.filter(&(&1 in @mine))
  end

  test "created window filters on original creation, not last update", %{ws: ws} do
    assert slugs(ws, []) == ["new-doc", "old-doc"]
    # Old was just edited but created 40 days ago → excluded by created:7d.
    assert slugs(ws, created: "7d") == ["new-doc"]
    assert slugs(ws, created: "90d") == ["new-doc", "old-doc"]
  end

  test "updated window filters on last activity", %{ws: ws} do
    # Both were touched recently (old via the edit), so both are in.
    assert slugs(ws, updated: "7d") == ["new-doc", "old-doc"]
  end

  test "created_at is populated as the v1 timestamp", %{ws: ws} do
    docs = Docs.list_current(ws.id)
    old = Enum.find(docs, &(&1.slug == "old-doc"))
    # created_at is ~40 days old; updated_at (current version) is recent.
    assert DateTime.diff(DateTime.utc_now(), old.created_at, :day) >= 39
    assert DateTime.diff(DateTime.utc_now(), old.updated_at, :day) == 0
  end

  test "sort :created orders by creation; :recent by update", %{ws: ws} do
    # By creation: new-doc (today) before old-doc (40d).
    assert ordered(ws, sort: :created) == ["new-doc", "old-doc"]
    # By recent (update): old-doc was edited last, so it's first.
    assert ordered(ws, sort: :recent) == ["old-doc", "new-doc"]
  end

  test "normalize_within grammar" do
    assert Docs.normalize_within("7d") == "7d"
    assert Docs.normalize_within(" 24h ") == "24h"
    assert Docs.normalize_within("0d") == nil
    assert Docs.normalize_within("400d") == nil
    assert Docs.normalize_within("x") == nil
    assert Docs.normalize_within(nil) == nil
  end
end
