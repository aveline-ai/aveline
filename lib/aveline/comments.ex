defmodule Aveline.Comments do
  @moduledoc """
  Doc comments, anchored to a specific doc version. Optionally pinned to a
  block. Every mutation publishes a PubSub event on the
  `doc:<base_doc_id>:comments` topic so subscribed LVs update live.
  """

  import Ecto.Query

  alias Aveline.Comments.Comment
  alias Aveline.Docs.Doc
  alias Aveline.Repo

  def base_query do
    from c in Comment, where: is_nil(c.deleted_at)
  end

  @doc """
  All non-deleted comments on a logical doc across ALL versions, oldest
  first. JOINs docs by base_doc_id so a comment posted on v3 still shows
  up on v4's page.
  """
  def list_for_base_doc(base_doc_id) when is_binary(base_doc_id) do
    from(c in base_query(),
      join: d in Doc,
      on: d.id == c.doc_id,
      where: d.base_doc_id == ^base_doc_id,
      order_by: [asc: c.inserted_at],
      preload: [:actor_user]
    )
    |> Repo.all()
  end

  def get_comment(id) when is_binary(id) do
    Repo.get(Comment, id) |> Repo.preload([:actor_user])
  end

  def create_comment(attrs) do
    %Comment{}
    |> Comment.create_changeset(attrs)
    |> Repo.insert()
    |> preload_and_broadcast(:comment_created)
  end

  def update_comment(%Comment{} = c, attrs) do
    c
    |> Comment.update_changeset(attrs)
    |> Repo.update()
    |> preload_and_broadcast(:comment_updated)
  end

  def soft_delete_comment(%Comment{} = c, deleted_by_id) do
    c
    |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(), deleted_by_id: deleted_by_id})
    |> Repo.update()
    |> preload_and_broadcast(:comment_deleted)
  end

  defp preload_and_broadcast({:ok, %Comment{} = c}, event) do
    c = Repo.preload(c, [:actor_user])

    base_doc_id =
      Repo.one(from d in Doc, where: d.id == ^c.doc_id, select: d.base_doc_id)

    if base_doc_id do
      Phoenix.PubSub.broadcast(
        Aveline.PubSub,
        "doc:" <> base_doc_id <> ":comments",
        {event, c}
      )
    end

    {:ok, c}
  end

  defp preload_and_broadcast(other, _), do: other
end
