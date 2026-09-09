defmodule Aveline.Gleam.Caps.Comments do
  @moduledoc """
  Real IO for src/aveline/caps/comments.gleam. Keep field order in
  lockstep.

  Mutation caps mirror the legacy Aveline.Comments write paths minus
  the decision logic (which now lives in the Gleam handlers): they
  mutate, preload, and broadcast the same PubSub message as before.
  Activity events are recorded by the handler via record_event, so the
  event's actor/action/data decisions stay in Gleam.
  """

  import Ecto.Query
  import Aveline.Gleam.Interop

  alias Aveline.Comments
  alias Aveline.Comments.Comment
  alias Aveline.Docs.Doc
  alias Aveline.Events
  alias Aveline.Repo
  alias Ecto.Multi

  def build do
    {:comments_caps,
     fn base_id -> opt(Comments.get_current_by_base(base_id), &to_gleam/1) end,
     fn base_id -> opt(Comments.get_latest_by_base(base_id), &to_gleam/1) end,
     fn doc_version_id ->
       doc_version_id |> Comments.list_for_doc_version() |> Enum.map(&to_view/1)
     end,
     &insert/1,
     &edit_body/2,
     fn row_id, resolver_id ->
       update_row(row_id, %{resolved_at: DateTime.utc_now(), resolved_by_id: resolver_id}, :comment_updated)
     end,
     fn row_id ->
       update_row(row_id, %{resolved_at: nil, resolved_by_id: nil}, :comment_updated)
     end,
     fn row_id, deleted_by_id ->
       update_row(row_id, %{deleted_at: DateTime.utc_now(), deleted_by_id: deleted_by_id}, :comment_deleted)
     end,
     fn row_id ->
       update_row(row_id, %{deleted_at: nil, deleted_by_id: nil}, :comment_updated)
     end,
     fn doc_version_id ->
       Doc
       |> Repo.get(doc_version_id)
       |> opt(fn d -> {:doc_ref, d.base_doc_id, d.workspace_id, d.slug, d.title} end)
     end,
     &record_event/1}
  end

  # ===== Mutations =====

  defp insert({:new_comment, doc_id, block_id, parent_comment_id, body, actor_user_id, actor_type}) do
    # v1: base_comment_id == id, version_number == 1. Pre-set the id so
    # base_comment_id can match it without a second update.
    id = Ecto.UUID.generate()

    attrs = %{
      "base_comment_id" => id,
      "version_number" => 1,
      "doc_id" => doc_id,
      "block_id" => unopt(block_id),
      "parent_comment_id" => unopt(parent_comment_id),
      "body" => body,
      "actor_user_id" => actor_user_id,
      "actor_type" => Atom.to_string(actor_type)
    }

    %Comment{id: id}
    |> Comment.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, comment} -> {:ok, comment |> broadcast(:comment_created) |> to_gleam()}
      {:error, _changeset} -> {:error, nil}
    end
  end

  defp edit_body(row_id, new_body) do
    current = Repo.get!(Comment, row_id)
    new_id = Ecto.UUID.generate()

    new_attrs = %{
      "base_comment_id" => current.base_comment_id,
      "version_number" => current.version_number + 1,
      "doc_id" => current.doc_id,
      "block_id" => current.block_id,
      "parent_comment_id" => current.parent_comment_id,
      "body" => new_body,
      "actor_user_id" => current.actor_user_id,
      "actor_type" => current.actor_type,
      "resolved_at" => current.resolved_at,
      "resolved_by_id" => current.resolved_by_id,
      "resolved_by_doc_id" => current.resolved_by_doc_id,
      "edited_at" => DateTime.utc_now()
    }

    # Supersede FIRST: the one-current-per-base unique index rejects a
    # second unsuperseded row, so order is load-bearing.
    Multi.new()
    |> Multi.update(:supersede, Ecto.Changeset.change(current, superseded: true))
    |> Multi.insert(:new_version, Comment.create_changeset(%Comment{id: new_id}, new_attrs))
    |> Repo.transaction()
    |> case do
      {:ok, %{new_version: new_version}} ->
        {:ok, new_version |> broadcast(:comment_updated) |> to_gleam()}

      {:error, _step, _err, _} ->
        {:error, nil}
    end
  end

  defp update_row(row_id, changes, event) do
    Comment
    |> Repo.get!(row_id)
    |> Ecto.Changeset.change(changes)
    |> Repo.update!()
    |> broadcast(event)
    |> to_gleam()
  end

  defp broadcast(%Comment{} = comment, event) do
    comment = Repo.preload(comment, [:actor_user, :resolved_by, :resolved_by_doc, :doc])

    base_doc_id =
      Repo.one(from d in Doc, where: d.id == ^comment.doc_id, select: d.base_doc_id)

    if base_doc_id do
      Phoenix.PubSub.broadcast(
        Aveline.PubSub,
        "doc:" <> base_doc_id <> ":comments",
        {event, comment}
      )
    end

    comment
  end

  # ===== Events =====

  defp record_event(
         {:comment_event_attrs, workspace_id, actor, actor_type, action, target_id, target_slug,
          target_label, doc_base_id, data}
       ) do
    data_map =
      case data do
        :no_data -> %{}
        {:resolved_by_doc, resolved_by_doc_id} -> %{"resolved_by_doc_id" => unopt(resolved_by_doc_id)}
        {:edit_version, version_number} -> %{"version_number" => version_number}
      end

    Events.record(%{
      workspace_id: workspace_id,
      actor: unopt(actor),
      actor_type: Atom.to_string(actor_type),
      action: action,
      target_kind: "comment",
      target_id: target_id,
      target_slug: target_slug,
      target_label: target_label,
      data: Map.put(data_map, "doc_base_id", doc_base_id)
    })

    nil
  end

  # ===== Conversions =====

  defp to_gleam(%Comment{} = c) do
    {:comment, c.id, c.base_comment_id, c.version_number, c.doc_id, opt(c.block_id),
     opt(c.parent_comment_id), c.body, c.actor_user_id, actor_type(c.actor_type),
     opt(c.resolved_at, &iso/1), opt(c.resolved_by_id), opt(c.resolved_by_doc_id),
     opt(c.edited_at, &iso/1), opt(c.deleted_at, &iso/1), opt(c.deleted_by_id)}
  end

  defp to_view(%Comment{} = c) do
    {:comment_view, c.base_comment_id, c.id, c.version_number, c.doc_id, opt(c.block_id),
     opt(c.parent_comment_id), c.body, c.actor_type, opt(c.actor_user, &user_ref/1),
     opt(c.resolved_at, &iso/1), opt(c.resolved_by, &user_ref/1),
     opt(c.resolved_by_doc, & &1.version_number), opt(c.edited_at, &iso/1),
     opt(c.deleted_at, &iso/1), opt(c.deleted_by, &user_ref/1), iso(c.inserted_at)}
  end

  defp user_ref(user),
    do: {:user_ref, user.id, user.username, opt(user.display_name), opt(user.email)}

  defp actor_type("human"), do: :human
  defp actor_type(_), do: :agent

  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
