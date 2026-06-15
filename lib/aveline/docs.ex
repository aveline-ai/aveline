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
  alias Aveline.Comments.Disposition
  alias Aveline.Docs.Doc
  alias Aveline.Events
  alias Aveline.Repo
  alias Aveline.Slug
  alias Ecto.Multi

  # ===== Read =====

  def base_query do
    from d in Doc, where: is_nil(d.deleted_at)
  end

  def list_current(workspace_id, opts \\ []) do
    pinned = Keyword.get(opts, :pinned, nil)
    pin_mode = Keyword.get(opts, :pin_mode, :pinned_first)
    sort = Keyword.get(opts, :sort, :recent)
    tags = Keyword.get(opts, :tags, []) || []
    owner_ids = Keyword.get(opts, :owner_ids, []) || []
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    base =
      from d in base_query(),
        where: d.workspace_id == ^workspace_id

    base
    |> apply_pin_filter(pinned)
    |> maybe_filter_tags(tags)
    |> maybe_filter_owners(owner_ids)
    |> apply_sort(sort, pin_mode)
    |> maybe_paginate(limit, offset)
    |> Repo.all()
    |> Repo.preload([:owner, :actor_user])
  end

  defp maybe_filter_owners(query, []), do: query
  defp maybe_filter_owners(query, ids), do: from(d in query, where: d.owner_id in ^ids)

  defp maybe_paginate(query, nil, _offset), do: query
  defp maybe_paginate(query, limit, 0), do: from(d in query, limit: ^limit)
  defp maybe_paginate(query, limit, offset),
    do: from(d in query, limit: ^limit, offset: ^offset)

  # `:pinned` boolean is the legacy API knob (used by saved views that
  # need to enforce pin filtering). Pin sorting is independent — see
  # `pin_mode` below. Sorts only sort; they never filter.
  defp apply_pin_filter(query, true), do: from(d in query, where: d.pinned == true)
  defp apply_pin_filter(query, false), do: from(d in query, where: d.pinned == false)
  defp apply_pin_filter(query, _), do: query

  # Sort modes:
  #   :recent → updated_at desc
  #   :kudos  → kudos count desc, then updated_at desc
  #   :views  → view count desc, then updated_at desc
  # Each respects pin_mode: pinned bubble to top unless `:interleave`.
  defp apply_sort(query, :recent, :interleave),
    do: from(d in query, order_by: [desc: d.updated_at])

  defp apply_sort(query, :recent, _pin_mode),
    do: from(d in query, order_by: [desc: d.pinned, desc: d.updated_at])

  defp apply_sort(query, :kudos, pin_mode), do: count_join_sort(query, "doc_kudos", pin_mode)
  defp apply_sort(query, :views, pin_mode), do: count_join_sort(query, "doc_views", pin_mode)

  defp count_join_sort(query, table, pin_mode) do
    q =
      from d in query,
        left_join: x in ^table,
        on: x.base_doc_id == d.base_doc_id,
        group_by: d.id

    if pin_mode == :interleave do
      from [d, x] in q,
        order_by: [desc: count(x.id), desc: d.updated_at]
    else
      from [d, x] in q,
        order_by: [desc: d.pinned, desc: count(x.id), desc: d.updated_at]
    end
  end

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

  # Distinct tags across all current (non-deleted) docs in a workspace,
  # sorted alphabetically. Used by the chip row on All Docs.
  def list_workspace_tags(workspace_id) do
    from(d in base_query(),
      where: d.workspace_id == ^workspace_id,
      select: fragment("DISTINCT UNNEST(?)", d.tags)
    )
    |> Repo.all()
    |> Enum.sort()
  end

@doc """
  Tag stats for the Tags management page: name, doc count, last-used at.
  Sorted by usage desc, then alpha for stability across reloads.
  """
  def list_tags_with_stats(workspace_id) do
    from(d in base_query(),
      where: d.workspace_id == ^workspace_id,
      select: %{
        tag: fragment("UNNEST(?)", d.tags),
        updated_at: d.updated_at
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.tag)
    |> Enum.map(fn {tag, rows} ->
      %{
        tag: tag,
        count: length(rows),
        last_used_at: rows |> Enum.map(& &1.updated_at) |> Enum.max(DateTime)
      }
    end)
    |> Enum.sort_by(fn %{count: c, tag: t} -> {-c, t} end)
  end

  @doc """
  Rename a tag across every current doc in the workspace. Idempotent: if
  no doc carries the old tag, returns `{:ok, 0}`. Returns affected count.

  Records a `tag_renamed` event on success.
  """
  def rename_tag(workspace_id, old_tag, new_tag, actor_user_id \\ nil)
      when is_binary(workspace_id) and is_binary(old_tag) and is_binary(new_tag) do
    new_tag = String.downcase(new_tag)

    with :ok <- Slug.validate(new_tag) do
      affected = mutate_tags(workspace_id, old_tag, fn tags -> rename_in(tags, old_tag, new_tag) end)

      if affected > 0 do
        Events.record(%{
          workspace_id: workspace_id,
          actor: actor_user_id,
          actor_type: "human",
          action: "tag_renamed",
          target_kind: "tag",
          target_label: new_tag,
          data: %{"from" => old_tag, "to" => new_tag, "affected" => affected}
        })
      end

      {:ok, affected}
    end
  end

  @doc """
  Merge `source_tag` into `target_tag` across every current doc. If a doc
  carries both, the source is dropped and the target stays. Returns
  affected count.

  Records a `tag_merged` event on success.
  """
  def merge_tags(workspace_id, source_tag, target_tag, actor_user_id \\ nil)
      when is_binary(workspace_id) and is_binary(source_tag) and is_binary(target_tag) do
    affected = mutate_tags(workspace_id, source_tag, fn tags -> rename_in(tags, source_tag, target_tag) end)

    if affected > 0 do
      Events.record(%{
        workspace_id: workspace_id,
        actor: actor_user_id,
        actor_type: "human",
        action: "tag_merged",
        target_kind: "tag",
        target_label: target_tag,
        data: %{"from" => source_tag, "into" => target_tag, "affected" => affected}
      })
    end

    {:ok, affected}
  end

  @doc """
  Strip `tag` from every current doc in the workspace. Records a
  `tag_deleted` event on success.
  """
  def delete_tag(workspace_id, tag, actor_user_id \\ nil)
      when is_binary(workspace_id) and is_binary(tag) do
    affected = mutate_tags(workspace_id, tag, fn tags -> List.delete(tags, tag) end)

    if affected > 0 do
      Events.record(%{
        workspace_id: workspace_id,
        actor: actor_user_id,
        actor_type: "human",
        action: "tag_deleted",
        target_kind: "tag",
        target_label: tag,
        data: %{"affected" => affected}
      })
    end

    {:ok, affected}
  end

  # Load every doc carrying `tag`, run the transform on its tags array,
  # write back. Bulk-via-rows because docs.tags is a `text[]` and we need
  # dedup/normalize after the transform — easier in Elixir than SQL.
  defp mutate_tags(workspace_id, tag, transform) do
    docs =
      from(d in base_query(),
        where: d.workspace_id == ^workspace_id and ^tag in d.tags
      )
      |> Repo.all()

    Enum.each(docs, fn doc ->
      new_tags = doc.tags |> transform.() |> Enum.uniq()

      doc
      |> Ecto.Changeset.change(%{tags: new_tags})
      |> Repo.update!()
    end)

    length(docs)
  end

  defp rename_in(tags, old, new) do
    Enum.map(tags, fn t -> if t == old, do: new, else: t end)
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
    # A brand-new doc has no prior comments — dispositions only matter on
    # subsequent versions. We still allow `dispositions: []` for symmetry.
    intent = Keyword.get(opts, :intent)
    dispositions = Keyword.get(opts, :dispositions, [])
    resolves = Keyword.get(opts, :resolves_comment_ids, [])

    new_attrs =
      base_attrs
      |> Map.put(:version_number, 1)
      |> Map.put(:blocks, new_blocks)
      |> Map.put(:operations, ops)
      |> Map.put(:intent, intent)
      |> Map.put(:resolves_comment_ids, resolves)
      |> Map.put(:comment_dispositions, Disposition.to_json(dispositions))

    Multi.new()
    |> Multi.insert(:doc, Doc.changeset(%Doc{}, new_attrs))
    |> Multi.run(:apply_dispositions, &apply_dispositions_step(&1, &2, dispositions, resolves))
    |> Repo.transaction()
    |> finish_apply()
  end

  defp insert_version(%Doc{} = current, new_blocks, ops, update_attrs, opts) do
    intent = Keyword.get(opts, :intent)
    actor_type = Map.fetch!(update_attrs, :actor_type)

    with {:ok, dispositions} <-
           resolve_dispositions(current, new_blocks, actor_type, opts) do
      now = DateTime.utc_now()
      resolves = derive_resolves(dispositions, opts)

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
        actor_type: actor_type,
        blocks: new_blocks,
        operations: ops,
        intent: intent,
        resolves_comment_ids: resolves,
        comment_dispositions: Disposition.to_json(dispositions)
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
      |> Multi.run(:apply_dispositions, &apply_dispositions_step(&1, &2, dispositions, resolves))
      |> Repo.transaction()
      |> finish_apply()
    end
  end

  # Validate dispositions against currently-open threads + new blocks.
  # Agents MUST cover every open thread. Humans may submit partial / no
  # dispositions; their fallback is `resolves_comment_ids` for back-compat.
  defp resolve_dispositions(%Doc{} = current, new_blocks, actor_type, opts) do
    raw = Keyword.get(opts, :dispositions, []) || []

    with {:ok, structs} <- cast_all(raw) do
      open_ids = open_thread_ids(current.base_doc_id)
      block_ids = collect_block_ids(new_blocks)

      cond do
        actor_type == "agent" ->
          case Disposition.validate(structs, open_ids, block_ids) do
            :ok -> {:ok, structs}
            err -> err
          end

        structs == [] ->
          {:ok, []}

        true ->
          case Disposition.validate(structs, open_ids, block_ids) do
            :ok -> {:ok, structs}
            {:error, {:disposition_coverage_mismatch, _}} -> {:ok, structs}
            err -> err
          end
      end
    end
  end

  defp cast_all(raw_list) do
    Enum.reduce_while(raw_list, {:ok, []}, fn raw, {:ok, acc} ->
      case Disposition.cast(raw) do
        {:ok, d} -> {:cont, {:ok, [d | acc]}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, structs} -> {:ok, Enum.reverse(structs)}
      err -> err
    end
  end

  defp open_thread_ids(base_doc_id) do
    from(c in Comment,
      join: d in Doc,
      on: d.id == c.doc_id,
      where:
        d.base_doc_id == ^base_doc_id and
          is_nil(c.parent_comment_id) and
          is_nil(c.resolved_at) and
          is_nil(c.deleted_at),
      select: c.id
    )
    |> Repo.all()
  end

  defp collect_block_ids(blocks) do
    Enum.flat_map(blocks, fn b -> if id = b["id"], do: [id], else: [] end)
  end

  defp derive_resolves(dispositions, opts) do
    explicit = Keyword.get(opts, :resolves_comment_ids, []) || []
    from_dispo = for %Disposition{action: "resolve", comment_id: id} <- dispositions, do: id
    Enum.uniq(explicit ++ from_dispo)
  end

  # Multi step: apply dispositions THEN fall back to legacy
  # resolves_comment_ids for anything not covered. Both run against the
  # just-inserted doc version so resolves carry resolved_by_doc_id.
  defp apply_dispositions_step(repo, %{doc: %Doc{id: doc_id, actor_user_id: uid}}, dispositions, resolves) do
    now = DateTime.utc_now()

    with {:ok, _} <- Disposition.apply(repo, dispositions, now, uid, doc_id) do
      dispo_ids = for %Disposition{action: "resolve", comment_id: id} <- dispositions, do: id
      leftover = Enum.uniq(resolves) -- dispo_ids

      {count, _} =
        from(c in Comment,
          where: c.id in ^leftover and is_nil(c.resolved_at) and is_nil(c.deleted_at)
        )
        |> repo.update_all(set: [resolved_at: now, resolved_by_id: uid, resolved_by_doc_id: doc_id])

      {:ok, count}
    end
  end

  defp finish_apply({:ok, %{doc: %Doc{} = doc}}) do
    doc = Repo.preload(doc, [:owner, :actor_user])
    Broadcasts.publish_doc_event(:doc_updated, doc)

    Events.record(%{
      workspace_id: doc.workspace_id,
      actor: doc.actor_user_id,
      actor_type: doc.actor_type,
      action: if(doc.version_number == 1, do: "doc_created", else: "doc_edited"),
      target_kind: "doc",
      target_id: doc.base_doc_id,
      target_slug: doc.slug,
      target_label: doc.title,
      data:
        %{"version" => doc.version_number, "tags" => doc.tags}
        |> maybe_put_intent(doc.intent)
    })

    {:ok, doc}
  end

  defp finish_apply({:error, _step, %Ecto.Changeset{} = cs, _changes}), do: {:error, cs}
  defp finish_apply({:error, _step, other, _changes}), do: {:error, other}

  defp maybe_put_intent(data, nil), do: data
  defp maybe_put_intent(data, ""), do: data
  defp maybe_put_intent(data, intent), do: Map.put(data, "intent", intent)

  # Pin / unpin updates `pinned` on the current version in place. Pin
  # state is workspace-navigation metadata, not content, so we don't mint
  # a new version row each toggle.
  def set_pinned(%Doc{} = current, pinned, actor_user_id \\ nil) when is_boolean(pinned) do
    current
    |> Ecto.Changeset.change(%{pinned: pinned})
    |> Repo.update()
    |> case do
      {:ok, doc} ->
        doc = Repo.preload(doc, [:owner, :actor_user])
        Broadcasts.publish_doc_event(:doc_updated, doc)

        Events.record(%{
          workspace_id: doc.workspace_id,
          actor: actor_user_id,
          actor_type: "human",
          action: if(pinned, do: "doc_pinned", else: "doc_unpinned"),
          target_kind: "doc",
          target_id: doc.base_doc_id,
          target_slug: doc.slug,
          target_label: doc.title
        })

        {:ok, doc}

      err ->
        err
    end
  end

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

        Events.record(%{
          workspace_id: doc.workspace_id,
          actor: deleted_by_id,
          actor_type: "human",
          action: "doc_deleted",
          target_kind: "doc",
          target_id: doc.base_doc_id,
          target_slug: doc.slug,
          target_label: doc.title
        })

        {:ok, doc}

      err ->
        err
    end
  end

  def restore(base_doc_id, actor_user_id \\ nil) when is_binary(base_doc_id) do
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

            Events.record(%{
              workspace_id: doc.workspace_id,
              actor: actor_user_id,
              actor_type: "human",
              action: "doc_restored",
              target_kind: "doc",
              target_id: doc.base_doc_id,
              target_slug: doc.slug,
              target_label: doc.title
            })

            {:ok, Repo.preload(doc, [:owner, :actor_user])}

          err ->
            err
        end
    end
  end
end
