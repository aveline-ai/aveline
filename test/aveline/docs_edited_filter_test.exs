defmodule Aveline.DocsEditedFilterTest do
  use Aveline.DataCase, async: false

  import Ecto.Query
  alias Aveline.{Docs, Fixtures, Repo}
  alias Aveline.Docs.Doc

  test "updated window filters by last-edited (current version) time" do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)

    fresh = Fixtures.doc_fixture(ws, user, slug: "fresh", title: "Fresh")
    stale = Fixtures.doc_fixture(ws, user, slug: "stale", title: "Stale")

    # Backdate the stale doc's current row to 40 days ago.
    long_ago = DateTime.add(DateTime.utc_now(), -40 * 24 * 3600, :second)

    Repo.update_all(
      from(d in Doc, where: d.base_doc_id == ^stale.base_doc_id),
      set: [updated_at: long_ago]
    )

    mine = fn opts ->
      ws.id
      |> Docs.list_current(opts)
      |> Enum.map(& &1.slug)
      |> Enum.filter(&(&1 in ["fresh", "stale"]))
      |> Enum.sort()
    end

    assert mine.([]) == ["fresh", "stale"]
    assert mine.(updated: "7d") == ["fresh"]
    assert mine.(updated: "90d") == ["fresh", "stale"]
    assert mine.(updated: "garbage") == ["fresh", "stale"]
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
