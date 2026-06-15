defmodule Aveline.Comments do
  @moduledoc """
  Doc comments, anchored to a specific doc version. Optionally pinned to a
  block. Every mutation publishes a PubSub event on the
  `doc:<base_doc_id>:comments` topic so subscribed LVs update live.
  """

  import Ecto.Query

  alias Aveline.Comments.Comment
  alias Aveline.Docs.Doc
  alias Aveline.Events
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
      preload: [:actor_user, :resolved_by, :resolved_by_doc, :doc]
    )
    |> Repo.all()
  end

  def get_comment(id) when is_binary(id) do
    Repo.get(Comment, id) |> Repo.preload([:actor_user, :resolved_by, :resolved_by_doc])
  end

  def resolve_comment(%Comment{} = c, resolver_id) do
    c
    |> Ecto.Changeset.change(%{
      resolved_at: DateTime.utc_now(),
      resolved_by_id: resolver_id
    })
    |> Repo.update()
    |> preload_and_broadcast(:comment_updated)
  end

  def unresolve_comment(%Comment{} = c) do
    c
    |> Ecto.Changeset.change(%{resolved_at: nil, resolved_by_id: nil})
    |> Repo.update()
    |> preload_and_broadcast(:comment_updated)
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
    c = Repo.preload(c, [:actor_user, :resolved_by, :resolved_by_doc, :doc])

    base_doc_id =
      Repo.one(from d in Doc, where: d.id == ^c.doc_id, select: d.base_doc_id)

    if base_doc_id do
      Phoenix.PubSub.broadcast(
        Aveline.PubSub,
        "doc:" <> base_doc_id <> ":comments",
        {event, c}
      )

      record_comment_event(event, c, base_doc_id)
    end

    {:ok, c}
  end

  defp preload_and_broadcast(other, _), do: other

  defp record_comment_event(event, %Comment{} = c, base_doc_id) do
    {actor_id, actor_type, action_data} =
      case event do
        :comment_created ->
          {c.actor_user_id, c.actor_type, %{}}

        :comment_updated when not is_nil(c.resolved_at) ->
          {c.resolved_by_id, "human",
           %{"resolved_by_doc_id" => c.resolved_by_doc_id}}

        :comment_updated ->
          # Reopen / edit body — credit to the comment's actor for now.
          {c.actor_user_id, c.actor_type, %{}}

        :comment_deleted ->
          {c.deleted_by_id, "human", %{}}
      end

    action =
      case event do
        :comment_created -> "comment_created"
        :comment_updated when not is_nil(c.resolved_at) -> "comment_resolved"
        :comment_updated -> "comment_unresolved"
        :comment_deleted -> "comment_deleted"
      end

    doc = c.doc

    Events.record(%{
      workspace_id: doc && doc.workspace_id,
      actor: actor_id,
      actor_type: actor_type,
      action: action,
      target_kind: "comment",
      target_id: c.id,
      target_slug: doc && doc.slug,
      target_label: doc && doc.title,
      data: Map.put(action_data, "doc_base_id", base_doc_id)
    })
  end
end
