defmodule Aveline.CommentsEditTest do
  use Aveline.DataCase, async: false

  alias Aveline.Comments
  alias Aveline.Comments.Comment
  alias Aveline.Fixtures
  alias Aveline.Repo

  defp setup_comment do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    doc = Fixtures.doc_fixture(ws, user)

    {:ok, c} =
      Comments.create_comment(%{
        "doc_id" => doc.id,
        "block_id" => nil,
        "body" => "first draft",
        "actor_user_id" => user.id,
        "actor_type" => "human"
      })

    %{user: user, ws: ws, doc: doc, comment: c}
  end

  describe "create_comment/1" do
    test "stamps base_comment_id == id and version_number = 1" do
      %{comment: c} = setup_comment()
      assert c.base_comment_id == c.id
      assert c.version_number == 1
    end
  end

  describe "edit_comment_body/3" do
    test "inserts a new version row, supersedes the prior, carries state forward" do
      %{user: user, comment: c} = setup_comment()

      assert {:ok, v2} = Comments.edit_comment_body(c, "second draft", user.id)

      assert v2.id != c.id
      assert v2.base_comment_id == c.base_comment_id
      assert v2.version_number == 2
      assert v2.body == "second draft"
      assert v2.edited_at != nil
      assert v2.actor_user_id == c.actor_user_id

      # Prior row is marked superseded (deleted_at set).
      reloaded_v1 = Repo.get!(Comment, c.id)
      assert reloaded_v1.deleted_at != nil
    end

    test "resolved state carries forward across an edit" do
      %{user: user, comment: c} = setup_comment()
      {:ok, resolved} = Comments.resolve_comment(c, user.id)

      assert {:ok, v2} = Comments.edit_comment_body(resolved, "typo fix", user.id)
      assert v2.resolved_at != nil
      assert v2.resolved_by_id == user.id
    end

    test "non-author cannot edit" do
      %{comment: c} = setup_comment()
      other = Fixtures.user_fixture()
      assert {:error, :forbidden} = Comments.edit_comment_body(c, "evil rewrite", other.id)
    end

    test "list_for_base_doc returns the current version only" do
      %{user: user, doc: doc, comment: c} = setup_comment()
      {:ok, _v2} = Comments.edit_comment_body(c, "second", user.id)
      {:ok, _v3} = Comments.edit_comment_body(Comments.get_current_by_base(c.base_comment_id), "third", user.id)

      messages = Comments.list_for_base_doc(doc.base_doc_id)
      bodies = Enum.map(messages, & &1.body)
      base_ids = Enum.map(messages, & &1.base_comment_id) |> Enum.uniq()

      assert bodies == ["third"]
      assert base_ids == [c.base_comment_id]
    end
  end

  describe "replies survive parent edits" do
    test "reply.parent_comment_id (base id) still resolves to the current parent after edit" do
      %{user: user, doc: doc, comment: parent} = setup_comment()

      {:ok, _reply} =
        Comments.create_comment(%{
          "doc_id" => doc.id,
          "parent_comment_id" => parent.base_comment_id,
          "body" => "agreed",
          "actor_user_id" => user.id,
          "actor_type" => "human"
        })

      {:ok, _v2_parent} = Comments.edit_comment_body(parent, "first draft (typo fix)", user.id)

      messages = Comments.list_for_base_doc(doc.base_doc_id)
      # Reply was inserted before the parent's v2, so sort puts it first.
      [reply, current_parent] = Enum.sort_by(messages, & &1.inserted_at)

      assert current_parent.version_number == 2
      assert current_parent.body == "first draft (typo fix)"
      assert reply.parent_comment_id == current_parent.base_comment_id
    end
  end
end
