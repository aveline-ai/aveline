defmodule Aveline.Items do
  @moduledoc """
  Items context. Every mutation is `apply_ops/4` — creates a new version
  row, marks the prior current row as superseded (deleted_at = NOW()), and
  broadcasts events. Comments that the version explicitly resolves are
  marked resolved in the same transaction.

  Read paths:
    * `list_current/2`         — current items in a workspace
    * `get_current_by_slug/2`  — current version by (workspace_id, slug)
    * `get_current_by_base/1`  — current version by base_item_id
    * `list_versions/1`        — all versions of a logical item, newest first
    * `get_version/2`          — a specific (base_item_id, version_number)
    * `related_items/2`        — same-workspace items sharing tags
  """

  import Ecto.Query

  alias Aveline.Broadcasts
  alias Aveline.Blocks.Document
  alias Aveline.Items.Item
  alias Aveline.Messages.ItemMessage
  alias Aveline.Repo
  alias Aveline.Slug
  alias Ecto.Multi

  # ===== Read =====

  def base_query do
    from i in Item, where: is_nil(i.deleted_at)
  end

  def list_current(workspace_id, opts \\ []) do
    pinned = Keyword.get(opts, :pinned, nil)
    tags = Keyword.get(opts, :tags, []) || []

    query =
      from i in base_query(),
        where: i.workspace_id == ^workspace_id,
        order_by: [desc: i.pinned, desc: i.updated_at],
        preload: [:owner, :actor_user]

    query
    |> maybe_filter_pinned(pinned)
    |> maybe_filter_tags(tags)
    |> Repo.all()
  end

  defp maybe_filter_pinned(query, true), do: from(i in query, where: i.pinned == true)
  defp maybe_filter_pinned(query, false), do: from(i in query, where: i.pinned == false)
  defp maybe_filter_pinned(query, _), do: query

  defp maybe_filter_tags(query, []), do: query

  defp maybe_filter_tags(query, tags) when is_list(tags) do
    from(i in query, where: fragment("? @> ?", i.tags, ^tags))
  end

  def get_current_by_slug(workspace_id, slug) when is_binary(slug) do
    from(i in base_query(),
      where: i.workspace_id == ^workspace_id and i.slug == ^slug,
      preload: [:owner, :actor_user]
    )
    |> Repo.one()
  end

  def get_current_by_base(base_item_id) when is_binary(base_item_id) do
    from(i in base_query(),
      where: i.base_item_id == ^base_item_id,
      preload: [:owner, :actor_user]
    )
    |> Repo.one()
  end

  def list_versions(base_item_id) when is_binary(base_item_id) do
    from(i in Item,
      where: i.base_item_id == ^base_item_id,
      order_by: [desc: i.version_number],
      preload: [:actor_user]
    )
    |> Repo.all()
  end

  def get_version(base_item_id, version_number)
      when is_binary(base_item_id) and is_integer(version_number) do
    from(i in Item,
      where: i.base_item_id == ^base_item_id and i.version_number == ^version_number,
      preload: [:owner, :actor_user]
    )
    |> Repo.one()
  end

  def get_item_by_id(id) when is_binary(id) do
    Repo.get(Item, id) |> Repo.preload([:owner, :actor_user])
  end

  @doc """
  Items in the same workspace sharing at least one tag with the source.
  Used for the related-notes panel.
  """
  def related_items(%Item{base_item_id: base, workspace_id: ws_id, tags: tags}, limit \\ 5)
      when is_list(tags) do
    if tags == [] do
      []
    else
      from(i in base_query(),
        where: i.workspace_id == ^ws_id and i.base_item_id != ^base,
        where: fragment("? && ?::varchar[]", i.tags, ^tags),
        order_by: [desc: i.pinned, desc: i.updated_at],
        limit: ^limit,
        preload: [:owner]
      )
      |> Repo.all()
    end
  end

  # ===== Write — single path =====

  @doc """
  Create a brand-new item from a list of initial blocks.

  Internally synthesizes a batch of `append_block` ops and routes through
  the same `apply_ops` pipeline so versions start at v1 with a real
  operations log.

  `attrs` keys (all required unless noted):
    * `:title`
    * `:slug`            (auto-derived from title if missing)
    * `:summary`         (optional)
    * `:tags`            (optional)
    * `:pinned`          (optional)
    * `:blocks`          (list of block maps, each will be validated + assigned ids)
    * `:workspace_id`
    * `:owner_id`
    * `:actor_user_id`
    * `:actor_type`      ("human" | "agent")
    * `:intent`          (optional, the diff_batch_intent)
  """
  def create_item(attrs) do
    base_item_id = Ecto.UUID.generate()

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
        base_item_id: base_item_id,
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

  @doc """
  Apply a batch of operations to a logical item.

  * For a NEW item: pass `:new` as the first argument with `base_attrs`
    set to all the per-item fields (workspace_id, slug, title, etc.).
  * For an EDIT: pass the current `%Item{}` as the first argument.
    `update_attrs` (in opts) may carry `title`, `summary`, `tags`, `pinned`
    overrides that come along with the version.

  Returns `{:ok, new_version_item}` or `{:error, reason}`.
  """
  def apply_ops(:new, ops, base_attrs, opts) when is_list(ops) and is_map(base_attrs) do
    case Document.apply_ops([], ops) do
      {:ok, new_blocks} ->
        insert_version(:new, new_blocks, ops, base_attrs, opts)

      {:error, reason, _idx} ->
        {:error, reason}
    end
  end

  def apply_ops(%Item{} = current, ops, update_attrs, opts)
      when is_list(ops) and is_map(update_attrs) do
    case Document.apply_ops(current.blocks || [], ops) do
      {:ok, new_blocks} ->
        insert_version(current, new_blocks, ops, update_attrs, opts)

      {:error, reason, _idx} ->
        {:error, reason}
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
    |> Multi.insert(:item, Item.changeset(%Item{}, new_attrs))
    |> Multi.run(:resolve, &resolve_comments(&1, &2, resolves))
    |> Repo.transaction()
    |> finish_apply()
  end

  defp insert_version(%Item{} = current, new_blocks, ops, update_attrs, opts) do
    intent = Keyword.get(opts, :intent)
    resolves = Keyword.get(opts, :resolves_comment_ids, [])
    now = DateTime.utc_now()

    new_attrs = %{
      base_item_id: current.base_item_id,
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
    |> Multi.insert(:item, Item.changeset(%Item{}, new_attrs))
    |> Multi.run(:resolve, &resolve_comments(&1, &2, resolves))
    |> Repo.transaction()
    |> finish_apply()
  end

  defp resolve_comments(_repo, _changes, []), do: {:ok, 0}

  defp resolve_comments(repo, %{item: %Item{actor_user_id: uid}}, ids) when is_list(ids) do
    now = DateTime.utc_now()

    {count, _} =
      from(m in ItemMessage,
        where: m.id in ^ids and is_nil(m.resolved_at) and is_nil(m.deleted_at)
      )
      |> repo.update_all(set: [resolved_at: now, resolved_by_id: uid])

    {:ok, count}
  end

  defp finish_apply({:ok, %{item: %Item{} = item}}) do
    item = Repo.preload(item, [:owner, :actor_user])
    Broadcasts.publish_item_event(:item_updated, item)
    {:ok, item}
  end

  defp finish_apply({:error, _step, %Ecto.Changeset{} = cs, _changes}), do: {:error, cs}
  defp finish_apply({:error, _step, other, _changes}), do: {:error, other}

  # ===== Delete / restore =====

  @doc """
  User-delete the whole logical item. Marks the current version row as
  deleted (deleted_by_id set to distinguish from a supersession), keeps
  all versions + comments around. Restore by `restore/2`.
  """
  def soft_delete(%Item{} = current, deleted_by_id) do
    current
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(),
      deleted_by_id: deleted_by_id
    })
    |> Repo.update()
    |> case do
      {:ok, item} ->
        Broadcasts.publish_item_event(:item_deleted, item)
        {:ok, item}

      err ->
        err
    end
  end

  @doc """
  Restore a user-deleted item — finds the latest version row for the
  base_item_id and unsets `deleted_at`.
  """
  def restore(base_item_id) when is_binary(base_item_id) do
    case Repo.one(
           from i in Item,
             where: i.base_item_id == ^base_item_id,
             order_by: [desc: i.version_number],
             limit: 1
         ) do
      nil ->
        {:error, :not_found}

      %Item{deleted_by_id: nil} ->
        # Not user-deleted (this row was just superseded); nothing to restore.
        {:error, :not_user_deleted}

      %Item{} = latest ->
        latest
        |> Ecto.Changeset.change(%{deleted_at: nil, deleted_by_id: nil})
        |> Repo.update()
        |> case do
          {:ok, item} ->
            Broadcasts.publish_item_event(:item_restored, item)
            {:ok, Repo.preload(item, [:owner, :actor_user])}

          err ->
            err
        end
    end
  end
end
