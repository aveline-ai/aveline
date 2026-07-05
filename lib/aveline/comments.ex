defmodule Aveline.Comments do
  @moduledoc """
  Doc comments. Versioned the same way docs are: each comment has a
  stable `base_comment_id` (logical thread node) and a per-version row;
  the CURRENT version of a comment is the one with `deleted_at IS NULL`
  for that base.

  - `create_comment/1`  — inserts v1; `base_comment_id` is auto-set to
    the new row's id.
  - `edit_comment_body/3` — inserts a new version row (v+1) carrying all
    prior state, then marks the previous row's `deleted_at` (superseded).
    Author-only.
  - `resolve_comment` / `unresolve_comment` / `soft_delete_comment` —
    update the current row in place. Resolve is a state change, not a
    new version of the comment's content.
  """

  import Ecto.Query

  alias Aveline.Comments.Comment
  alias Aveline.Docs.Doc
  alias Aveline.Events
  alias Aveline.Repo
  alias Ecto.Multi

  def base_query do
    from c in Comment, where: not c.superseded and is_nil(c.deleted_at)
  end

  @doc """
  All CURRENT-version comments on a logical doc across ALL doc versions,
  oldest first. Used by callers that don't care which doc-version they're
  rendering — they want every live comment thread visible right now.
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

  @doc """
  The comment snapshot pinned to a specific doc-version. Each comment-
  version row carries a `doc_id` pointing at the doc-version it was
  created on (or auto-forwarded to). Filtering by that gives us the
  exact set of comments visible "as of" that doc-version — what
  someone time-traveling there should see.

  Pass the doc-version row's `id` (NOT the base_doc_id).

  We do NOT filter on `superseded` here, because a row that's
  the canonical snapshot for doc-version N may still get `superseded`
  set later (when doc-version N+1 ships and auto-forwards everything).
  Instead we use DISTINCT ON to pick the latest comment-version row per
  base within this doc-version (handles same-doc-version body edits).
  """
  def list_for_doc_version(doc_version_id, opts \\ []) when is_binary(doc_version_id) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    base =
      from c in Comment,
        distinct: c.base_comment_id,
        where: c.doc_id == ^doc_version_id,
        order_by: [asc: c.base_comment_id, desc: c.version_number]

    query =
      if include_deleted, do: base, else: from(c in base, where: is_nil(c.deleted_at))

    query
    |> Repo.all()
    |> Enum.sort_by(& &1.inserted_at)
    |> Repo.preload([:actor_user, :resolved_by, :resolved_by_doc, :doc, :deleted_by])
  end

  @doc """
  Open top-level threads on the live docs a user OWNS in a workspace,
  newest first. This is the maintenance queue: you own the doc, so you
  own answering (or dispositioning) what's open on it. Returns
  `{comment, doc}` pairs so callers can link back to the doc (and
  block) the thread anchors to.
  """
  def list_open_threads_for_owner(workspace_id, owner_id, limit \\ 5) do
    # A comment pins the doc-version it was made on, which may be
    # superseded by later edits — so liveness is judged on the base's
    # CURRENT version (joined via the pin), and that's also the row
    # returned, so links land on the doc as it is now.
    from(c in base_query(),
      join: pinned in Doc,
      on: pinned.id == c.doc_id,
      join: d in Doc,
      on: d.base_doc_id == pinned.base_doc_id and not d.superseded and is_nil(d.deleted_at),
      where: d.workspace_id == ^workspace_id and d.owner_id == ^owner_id,
      where: is_nil(c.parent_comment_id) and is_nil(c.resolved_at),
      order_by: [desc: c.inserted_at],
      limit: ^limit,
      preload: [:actor_user],
      select: {c, d}
    )
    |> Repo.all()
  end

  @doc "Fetch by row id (a specific version). Mostly for callers that already hold a row id."
  def get_comment(id) when is_binary(id) do
    Repo.get(Comment, id) |> Repo.preload([:actor_user, :resolved_by, :resolved_by_doc])
  end

  @doc """
  Fetch the CURRENT version of a comment by its logical (base) id.
  This is what most external callers should use — disposition handlers,
  edit/delete flows, etc. — so they always operate on the live row.
  The live row = neither superseded nor deleted.
  """
  def get_current_by_base(base_id) when is_binary(base_id) do
    from(c in Comment,
      where:
        c.base_comment_id == ^base_id and not c.superseded and
          is_nil(c.deleted_at)
    )
    |> Repo.one()
    |> case do
      nil -> nil
      c -> Repo.preload(c, [:actor_user, :resolved_by, :resolved_by_doc])
    end
  end

  @doc """
  Fetch the latest comment-version row for a base id, regardless of
  whether it's currently deleted. Used by the undelete path so we can
  flip `deleted_at` back to nil on the row that was last deleted.
  """
  def get_latest_by_base(base_id) when is_binary(base_id) do
    from(c in Comment,
      where: c.base_comment_id == ^base_id and not c.superseded
    )
    |> Repo.one()
    |> case do
      nil -> nil
      c -> Repo.preload(c, [:actor_user, :resolved_by, :resolved_by_doc, :deleted_by])
    end
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
    # v1: base_comment_id == id, version_number == 1. We pre-set the id
    # on the struct (Ecto skips autogenerate when it's already set) so
    # base_comment_id can match it without a second update.
    id = Ecto.UUID.generate()

    attrs =
      attrs
      |> stringify()
      |> Map.put("base_comment_id", id)
      |> Map.put("version_number", 1)

    %Comment{id: id}
    |> Comment.create_changeset(attrs)
    |> Repo.insert()
    |> preload_and_broadcast(:comment_created)
  end

  @doc """
  Edit a comment's body — author-only. Inserts a new version row
  (v+1) carrying every other field forward (block_id, parent ref,
  resolved_at / resolved_by_doc_id, etc. — so a resolved comment stays
  resolved across an edit). The prior row gets `superseded` set
  (not `deleted_at`) in the same transaction; that's a mechanism flag,
  not a user-delete.

  `doc_id` carry-over note: today this preserves the prior row's
  doc_id. After the auto-forward refactor lands (Phase 2 of the
  current build), edits will pin to the current doc-version at edit
  time so time-travel renders correctly.
  """
  def edit_comment_body(%Comment{} = current, new_body, editor_id) do
    cond do
      current.actor_user_id != editor_id ->
        {:error, :forbidden}

      not is_nil(current.deleted_at) or current.superseded ->
        {:error, :stale_version}

      true ->
        now = DateTime.utc_now()
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
          "edited_at" => now
        }

        # Supersede FIRST: the one-current-per-base unique index rejects
        # a second unsuperseded row, so order is load-bearing.
        Multi.new()
        |> Multi.update(:supersede, Ecto.Changeset.change(current, superseded: true))
        |> Multi.insert(:new_version, Comment.create_changeset(%Comment{id: new_id}, new_attrs))
        |> Repo.transaction()
        |> case do
          {:ok, %{new_version: new_v}} -> preload_and_broadcast({:ok, new_v}, :comment_updated)
          {:error, _, err, _} -> {:error, err}
        end
    end
  end

  def soft_delete_comment(%Comment{} = c, deleted_by_id) do
    c
    |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(), deleted_by_id: deleted_by_id})
    |> Repo.update()
    |> preload_and_broadcast(:comment_deleted)
  end

  @doc """
  Reverse a soft-delete. The row stays the same; we just clear the
  deletion flags. State-flag mutation, in-place — symmetric with
  resolve/unresolve.
  """
  def undelete_comment(%Comment{} = c) do
    c
    |> Ecto.Changeset.change(%{deleted_at: nil, deleted_by_id: nil})
    |> Repo.update()
    |> preload_and_broadcast(:comment_updated)
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

        :comment_updated when not is_nil(c.resolved_at) and c.version_number == 1 ->
          {c.resolved_by_id, "human", %{"resolved_by_doc_id" => c.resolved_by_doc_id}}

        :comment_updated when c.version_number > 1 ->
          # Edit — author rewrote the body. Credit to the comment's actor.
          {c.actor_user_id, c.actor_type, %{"version_number" => c.version_number}}

        :comment_updated ->
          # Resolve / unresolve via in-place update.
          {c.actor_user_id, c.actor_type, %{}}

        :comment_deleted ->
          {c.deleted_by_id, "human", %{}}
      end

    action =
      case event do
        :comment_created -> "comment_created"
        :comment_updated when c.version_number > 1 -> "comment_edited"
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
      target_id: c.base_comment_id,
      target_slug: doc && doc.slug,
      target_label: doc && doc.title,
      data: Map.put(action_data, "doc_base_id", base_doc_id)
    })
  end

  defp stringify(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
