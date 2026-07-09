defmodule Aveline.DocViewsRecentTest do
  use Aveline.DataCase, async: false

  alias Aveline.Docs
  alias Aveline.DocViews
  alias Aveline.Fixtures

  setup do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    %{user: user, ws: ws}
  end

  # record/4 dedupes within an hour, so seed rows directly to control
  # ordering.
  defp view!(ws, doc, user, seconds_ago, actor \\ "human") do
    Repo.insert!(%Aveline.DocViews.DocView{
      workspace_id: ws.id,
      base_doc_id: doc.base_doc_id,
      user_id: user.id,
      actor_type: actor,
      viewed_at: DateTime.add(DateTime.utc_now(), -seconds_ago, :second)
    })
  end

  test "returns the user's last distinct docs, most recent first", %{user: user, ws: ws} do
    [a, b, c, d] = for t <- ~w(A B C D), do: Fixtures.doc_fixture(ws, user, title: t)

    view!(ws, a, user, 400)
    view!(ws, b, user, 300)
    view!(ws, c, user, 200)
    view!(ws, d, user, 100)
    # Re-reading an old doc bumps it to the front.
    view!(ws, a, user, 10)

    titles = ws.id |> DocViews.recent_for_user(user.id, 3) |> Enum.map(fn {doc, _} -> doc.title end)
    assert titles == ["A", "D", "C"]
  end

  test "agent reads under the same user don't count", %{user: user, ws: ws} do
    human_doc = Fixtures.doc_fixture(ws, user, title: "Human read")
    agent_doc = Fixtures.doc_fixture(ws, user, title: "Agent read")

    view!(ws, human_doc, user, 100)
    view!(ws, agent_doc, user, 10, "agent")

    titles = ws.id |> DocViews.recent_for_user(user.id, 3) |> Enum.map(fn {doc, _} -> doc.title end)
    assert titles == ["Human read"]
  end

  test "deleted docs drop out", %{user: user, ws: ws} do
    doc = Fixtures.doc_fixture(ws, user, title: "Doomed")
    view!(ws, doc, user, 10)
    {:ok, _} = Docs.soft_delete(doc, user.id)

    assert DocViews.recent_for_user(ws.id, user.id, 3) == []
  end

  test "scoped to the workspace", %{user: user, ws: ws} do
    other_ws = Fixtures.workspace_fixture(user)
    doc = Fixtures.doc_fixture(other_ws, user, title: "Elsewhere")
    view!(other_ws, doc, user, 10)

    assert DocViews.recent_for_user(ws.id, user.id, 3) == []
  end

  test "an edited doc appears once, on its current version", %{user: user, ws: ws} do
    doc = Fixtures.doc_fixture(ws, user, title: "Edited a lot")
    view!(ws, doc, user, 10)

    ops = [
      %{"op" => "append_block", "block" => %{"type" => "paragraph", "content" => [%{"text" => "more"}]}}
    ]

    {:ok, v2} = Docs.apply_ops(doc, ops, %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])
    {:ok, _v3} = Docs.apply_ops(v2, ops, %{actor_user_id: user.id, actor_type: "agent"}, dispositions: [])

    assert [{d, _}] = DocViews.recent_for_user(ws.id, user.id, 5)
    assert d.version_number == 3
  end
end
