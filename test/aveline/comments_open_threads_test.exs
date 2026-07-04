defmodule Aveline.CommentsOpenThreadsTest do
  use Aveline.DataCase, async: false

  alias Aveline.Comments
  alias Aveline.Fixtures

  setup do
    owner = Fixtures.user_fixture()
    other = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(owner)
    {:ok, _} = Aveline.Workspaces.ensure_member(ws.id, other.id)
    %{owner: owner, other: other, ws: ws}
  end

  defp comment!(doc, author, body) do
    {:ok, c} =
      Comments.create_comment(%{
        "doc_id" => doc.id,
        "body" => body,
        "actor_user_id" => author.id,
        "actor_type" => "human"
      })

    c
  end

  test "only threads on docs the user owns", %{owner: owner, other: other, ws: ws} do
    mine = Fixtures.doc_fixture(ws, owner, title: "Mine")
    theirs = Fixtures.doc_fixture(ws, other, title: "Theirs")

    comment!(mine, other, "question on your doc")
    comment!(theirs, owner, "question on their doc")

    bodies =
      ws.id
      |> Comments.list_open_threads_for_owner(owner.id)
      |> Enum.map(fn {c, _d} -> c.body end)

    assert bodies == ["question on your doc"]
  end

  test "resolved threads and replies don't show", %{owner: owner, other: other, ws: ws} do
    mine = Fixtures.doc_fixture(ws, owner, title: "Mine")

    open = comment!(mine, other, "still open")
    resolved = comment!(mine, other, "already handled")
    {:ok, _} = Comments.resolve_comment(resolved, owner.id)

    {:ok, _reply} =
      Comments.create_comment(%{
        "doc_id" => mine.id,
        "parent_comment_id" => open.base_comment_id,
        "body" => "a reply, not a thread",
        "actor_user_id" => owner.id,
        "actor_type" => "human"
      })

    bodies =
      ws.id
      |> Comments.list_open_threads_for_owner(owner.id)
      |> Enum.map(fn {c, _d} -> c.body end)

    assert bodies == ["still open"]
  end
end
