defmodule Aveline.Docs do
  @moduledoc """
  Docs context. Every mutation is `apply_ops/4` — creates a new version
  row, marks the prior current row as superseded (deleted_at = NOW()), and
  broadcasts events. Comments that the version explicitly resolves are
  marked resolved in the same transaction.

  Read paths:
    * `list_current/2`         — current docs in a workspace
    * `get_current_by_slug/2`  — current version by (workspace_id, slug)
    * `get_current_by_base/1`  — current version by base_doc_id
    * `list_versions/1`        — all versions of a logical doc, newest first
    * `get_version/2`          — a specific (base_doc_id, version_number)
    * `related_docs/2`         — same-workspace docs sharing tags
  """

  import Ecto.Query

  alias Aveline.Broadcasts
  alias Aveline.Blocks.Document
  alias Aveline.Comments.Comment
  alias Aveline.Docs.Doc
  alias Aveline.Repo
  alias Aveline.Slug
  alias Ecto.Multi

  # ===== Read =====

  def base_query do
    from d in Doc, where: is_nil(d.deleted_at)
  end

  def list_current(workspace_id, opts \\ []) do
    pinned = Keyword.get(opts, :pinned, nil)
    tags = Keyword.get(opts, :tags, []) || []

    query =
      from d in base_query(),
        where: d.workspace_id == ^workspace_id,
        order_by: [desc: d.pinned, desc: d.updated_at],
        preload: [:owner, :actor_user]

    query
    |> maybe_filter_pinned(pinned)
    |> maybe_filter_tags(tags)
    |> Repo.all()
  end

  defp maybe_filter_pinned(query, true), do: from(d in query, where: d.pinned == true)
  defp maybe_filter_pinned(query, false), do: from(d in query, where: d.pinned == false)
  defp maybe_filter_pinned(query, _), do: query

  defp maybe_filter_tags(query, []), do: query

  defp maybe_filter_tags(query, tags) when is_list(tags) do
    from(d in query, where: fragment("? @> ?", d.tags, ^tags))
  end

  def get_current_by_slug(workspace_id, slug) when is_binary(slug) do
    from(d in base_query(),
      where: d.workspace_id == ^workspace_id and d.slug == ^slug,
      preload: [:owner, :actor_user]
    )
    |> Repo.one()
  end

  def get_current_by_base(base_doc_id) when is_binary(base_doc_id) do
    from(d in base_query(),
      where: d.base_doc_id == ^base_doc_id,
      preload: [:owner, :actor_user]
    )
    |> Repo.one()
  end

  def list_versions(base_doc_id) when is_binary(base_doc_id) do
    from(d in Doc,
      where: d.base_doc_id == ^base_doc_id,
      order_by: [desc: d.version_number],
      preload: [:actor_user]
    )
    |> Repo.all()
  end

  def get_version(base_doc_id, version_number)
      when is_binary(base_doc_id) and is_integer(version_number) do
    from(d in Doc,
      where: d.base_doc_id == ^base_doc_id and d.version_number == ^version_number,
      preload: [:owner, :actor_user]
    )
    |> Repo.one()
  end

  def get_doc_by_id(id) when is_binary(id) do
    Repo.get(Doc, id) |> Repo.preload([:owner, :actor_user])
  end

  @doc """
  Docs in the same workspace sharing at least one tag with the source.
  Used for the related-docs panel.
  """
  def related_docs(%Doc{base_doc_id: base, workspace_id: ws_id, tags: tags}, limit \\ 5)
      when is_list(tags) do
    if tags == [] do
      []
    else
      from(d in base_query(),
        where: d.workspace_id == ^ws_id and d.base_doc_id != ^base,
        where: fragment("? && ?::varchar[]", d.tags, ^tags),
        order_by: [desc: d.pinned, desc: d.updated_at],
        limit: ^limit,
        preload: [:owner]
      )
      |> Repo.all()
    end
  end

  # ===== Write — single path =====

  def create_doc(attrs) do
    base_doc_id = Ecto.UUID.generate()

    title = Map.get(attrs, :title) || ""
    slug = Map.get(attrs, :slug) || Slug.derive(title)

    if slug in [nil, ""] do
      {:error, "could not derive slug from title"}
    else
      ops =
        attrs
        |> Map.get(:blocks, [])
        |> Enum.map(fn block ->
          %{"op" => "append_block", "block" => Map.new(block, &stringify_kv/1)}
        end)

      base_attrs = %{
        base_doc_id: base_doc_id,
        workspace_id: Map.fetch!(attrs, :workspace_id),
        slug: slug,
        title: title,
        summary: Map.get(attrs, :summary),
        tags: Map.get(attrs, :tags, []),
        pinned: Map.get(attrs, :pinned, false),
        owner_id: Map.fetch!(attrs, :owner_id),
        actor_user_id: Map.fetch!(attrs, :actor_user_id),
        actor_type: Map.fetch!(attrs, :actor_type)
      }

      intent = Map.get(attrs, :intent) || "create"
      apply_ops(:new, ops, base_attrs, intent: intent, resolves_comment_ids: [])
    end
  end

  defp stringify_kv({k, v}) when is_atom(k), do: {Atom.to_string(k), v}
  defp stringify_kv(kv), do: kv

  def apply_ops(:new, ops, base_attrs, opts) when is_list(ops) and is_map(base_attrs) do
    case Document.apply_ops([], ops) do
      {:ok, new_blocks} -> insert_version(:new, new_blocks, ops, base_attrs, opts)
      {:error, reason, _idx} -> {:error, reason}
    end
  end

  def apply_ops(%Doc{} = current, ops, update_attrs, opts)
      when is_list(ops) and is_map(update_attrs) do
    case Document.apply_ops(current.blocks || [], ops) do
      {:ok, new_blocks} -> insert_version(current, new_blocks, ops, update_attrs, opts)
      {:error, reason, _idx} -> {:error, reason}
    end
  end

  defp insert_version(:new, new_blocks, ops, base_attrs, opts) do
    intent = Keyword.get(opts, :intent)
    resolves = Keyword.get(opts, :resolves_comment_ids, [])

    new_attrs =
      base_attrs
      |> Map.put(:version_number, 1)
      |> Map.put(:blocks, new_blocks)
      |> Map.put(:operations, ops)
      |> Map.put(:intent, intent)
      |> Map.put(:resolves_comment_ids, resolves)

    Multi.new()
    |> Multi.insert(:doc, Doc.changeset(%Doc{}, new_attrs))
    |> Multi.run(:resolve, &resolve_comments(&1, &2, resolves))
    |> Repo.transaction()
    |> finish_apply()
  end

  defp insert_version(%Doc{} = current, new_blocks, ops, update_attrs, opts) do
    intent = Keyword.get(opts, :intent)
    resolves = Keyword.get(opts, :resolves_comment_ids, [])
    now = DateTime.utc_now()

    new_attrs = %{
      base_doc_id: current.base_doc_id,
      version_number: current.version_number + 1,
      workspace_id: current.workspace_id,
      slug: current.slug,
      title: Map.get(update_attrs, :title, current.title),
      summary: Map.get(update_attrs, :summary, current.summary),
      tags: Map.get(update_attrs, :tags, current.tags),
      pinned: Map.get(update_attrs, :pinned, current.pinned),
      owner_id: current.owner_id,
      actor_user_id: Map.fetch!(update_attrs, :actor_user_id),
      actor_type: Map.fetch!(update_attrs, :actor_type),
      blocks: new_blocks,
      operations: ops,
      intent: intent,
      resolves_comment_ids: resolves
    }

    Multi.new()
    |> Multi.update(
      :supersede,
      Ecto.Changeset.change(current,
        deleted_at: now,
        deleted_by_id: Map.get(update_attrs, :actor_user_id)
      )
    )
    |> Multi.insert(:doc, Doc.changeset(%Doc{}, new_attrs))
    |> Multi.run(:resolve, &resolve_comments(&1, &2, resolves))
    |> Repo.transaction()
    |> finish_apply()
  end

  defp resolve_comments(_repo, _changes, []), do: {:ok, 0}

  defp resolve_comments(repo, %{doc: %Doc{actor_user_id: uid}}, ids) when is_list(ids) do
    now = DateTime.utc_now()

    {count, _} =
      from(c in Comment,
        where: c.id in ^ids and is_nil(c.resolved_at) and is_nil(c.deleted_at)
      )
      |> repo.update_all(set: [resolved_at: now, resolved_by_id: uid])

    {:ok, count}
  end

  defp finish_apply({:ok, %{doc: %Doc{} = doc}}) do
    doc = Repo.preload(doc, [:owner, :actor_user])
    Broadcasts.publish_doc_event(:doc_updated, doc)
    {:ok, doc}
  end

  defp finish_apply({:error, _step, %Ecto.Changeset{} = cs, _changes}), do: {:error, cs}
  defp finish_apply({:error, _step, other, _changes}), do: {:error, other}

  # ===== Delete / restore =====

  def soft_delete(%Doc{} = current, deleted_by_id) do
    current
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(),
      deleted_by_id: deleted_by_id
    })
    |> Repo.update()
    |> case do
      {:ok, doc} ->
        Broadcasts.publish_doc_event(:doc_deleted, doc)
        {:ok, doc}

      err ->
        err
    end
  end

  def restore(base_doc_id) when is_binary(base_doc_id) do
    case Repo.one(
           from d in Doc,
             where: d.base_doc_id == ^base_doc_id,
             order_by: [desc: d.version_number],
             limit: 1
         ) do
      nil ->
        {:error, :not_found}

      %Doc{deleted_by_id: nil} ->
        {:error, :not_user_deleted}

      %Doc{} = latest ->
        latest
        |> Ecto.Changeset.change(%{deleted_at: nil, deleted_by_id: nil})
        |> Repo.update()
        |> case do
          {:ok, doc} ->
            Broadcasts.publish_doc_event(:doc_restored, doc)
            {:ok, Repo.preload(doc, [:owner, :actor_user])}

          err ->
            err
        end
    end
  end
end
