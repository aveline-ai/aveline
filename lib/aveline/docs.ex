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
  alias Aveline.Tags
  alias Ecto.Multi

  # ===== Read =====

  # Live = current version (not superseded) and not human-deleted.
  def base_query do
    from d in Doc, where: not d.superseded and is_nil(d.deleted_at)
  end

  def list_current(workspace_id, opts \\ []) do
    sort = Keyword.get(opts, :sort, :recent)
    tags = Keyword.get(opts, :tags, []) || []
    owner_ids = Keyword.get(opts, :owner_ids, []) || []
    has = Keyword.get(opts, :has, []) || []
    search = (Keyword.get(opts, :search) || "") |> to_string() |> String.trim()
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    base =
      from d in base_query(),
        where: d.workspace_id == ^workspace_id

    base
    |> maybe_filter_tags(tags)
    |> maybe_filter_owners(owner_ids)
    |> maybe_filter_has(has)
    |> maybe_filter_search(search)
    |> apply_sort(sort)
    |> maybe_paginate(limit, offset)
    |> Repo.all()
    |> Repo.preload([:owner, :actor_user])
    |> scrub_deleted_tags(workspace_id)
  end

  # Soft-deleted tags stay on doc rows (so restoring a tag brings every
  # attachment back) but are invisible to current reads — scrubbed here
  # at the read boundary. Historical version reads keep raw tags. A doc
  # edited while a tag is deleted persists the scrubbed set — the
  # visible set at edit time is the honest one.
  defp scrub_deleted_tags(docs, workspace_id) when is_list(docs) do
    live = Tags.live_slug_set(workspace_id)

    Enum.map(docs, fn d ->
      %{d | tags: Enum.filter(d.tags || [], &MapSet.member?(live, &1))}
    end)
  end

  defp scrub_deleted_tags(nil, _workspace_id), do: nil

  defp scrub_deleted_tags(%Doc{} = doc, workspace_id),
    do: docs_scrub_one(doc, workspace_id)

  defp docs_scrub_one(doc, workspace_id) do
    [scrubbed] = scrub_deleted_tags([doc], workspace_id)
    scrubbed
  end

  @doc "Structural doc kinds the `has:` filter understands."
  def has_kinds, do: ~w(board)

  # Structural kind filter: a doc is a board because of what's in its
  # blocks (jsonb containment). Links are just what documents do, not a
  # kind worth filtering on.
  defp maybe_filter_has(query, []), do: query

  defp maybe_filter_has(query, kinds) when is_list(kinds) do
    Enum.reduce(kinds, query, fn
      "board", q ->
        from(d in q, where: fragment("? @> '[{\"type\": \"board\"}]'::jsonb", d.blocks))

      _, q ->
        q
    end)
  end

  # Postgres full-text: websearch_to_tsquery handles the user-facing syntax
  # (phrase in quotes, -word to exclude, OR for either). Matches against
  # the `search_text` column via the GIN index.
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, q) do
    from d in query,
      where:
        fragment(
          "to_tsvector('english', ?) @@ websearch_to_tsquery('english', ?)",
          d.search_text,
          ^q
        )
  end

  defp maybe_filter_owners(query, []), do: query
  defp maybe_filter_owners(query, ids), do: from(d in query, where: d.owner_id in ^ids)

  defp maybe_paginate(query, nil, _offset), do: query
  defp maybe_paginate(query, limit, 0), do: from(d in query, limit: ^limit)

  defp maybe_paginate(query, limit, offset),
    do: from(d in query, limit: ^limit, offset: ^offset)

  # Sort modes:
  #   :recent → updated_at desc
  #   :kudos  → kudos count desc, then updated_at desc
  #   :views  → view count desc, then updated_at desc
  # Pins are a home-page concept; they don't influence list ordering.
  defp apply_sort(query, :recent),
    do: from(d in query, order_by: [desc: d.updated_at])

  defp apply_sort(query, :kudos), do: count_join_sort(query, "doc_kudos")
  defp apply_sort(query, :views), do: count_join_sort(query, "doc_views")

  defp count_join_sort(query, table) do
    from d in query,
      left_join: x in ^table,
      on: x.base_doc_id == d.base_doc_id,
      group_by: d.id,
      order_by: [desc: count(x.id), desc: d.updated_at]
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
    |> scrub_deleted_tags(workspace_id)
  end

  def get_current_by_base(base_doc_id) when is_binary(base_doc_id) do
    from(d in base_query(),
      where: d.base_doc_id == ^base_doc_id,
      preload: [:owner, :actor_user]
    )
    |> Repo.one()
    |> case do
      nil -> nil
      doc -> scrub_deleted_tags(doc, doc.workspace_id)
    end
  end

  # Distinct LIVE tags across all current (non-deleted) docs in a
  # workspace, sorted alphabetically. Feeds the Docs filter dropdowns.
  def list_workspace_tags(workspace_id) do
    live = Tags.live_slug_set(workspace_id)

    from(d in base_query(),
      where: d.workspace_id == ^workspace_id,
      select: fragment("DISTINCT UNNEST(?)", d.tags)
    )
    |> Repo.all()
    |> Enum.filter(&MapSet.member?(live, &1))
    |> Enum.sort()
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
        order_by: [desc: d.updated_at],
        limit: ^limit,
        preload: [:owner]
      )
      |> Repo.all()
    end
  end

  # ===== Orientation doc =====
  # Every workspace carries exactly one orientation doc — "how we use
  # Aveline here" — marked by the `orientation` boolean on the doc row.
  # One per workspace (partial unique index) and undeletable by CHECK
  # constraint, not convention. Ordinary in every other way: versioned,
  # commentable, doc_links welcome. Seeded at workspace creation; it's
  # the one stable thing a fresh agent can fetch to orient itself.

  # Home-page pins: 6 numbered slots per workspace. Pinning means
  # exactly one thing — this doc holds that slot on the home page, in
  # that position. The orientation doc has its own card above the shelf
  # and never takes a slot. Slot state lives on the current version row
  # and is mutated in place (navigation metadata, not content — same
  # treatment set_pinned always had).
  @pin_limit 6

  @doc "Number of home-page pin slots per workspace."
  def pin_limit, do: @pin_limit

  @doc "The workspace's pinned docs, in slot order."
  def list_pinned(workspace_id) do
    from(d in base_query(),
      where: d.workspace_id == ^workspace_id and not is_nil(d.pin_slot),
      order_by: [asc: d.pin_slot],
      preload: [:owner, :actor_user]
    )
    |> Repo.all()
    |> scrub_deleted_tags(workspace_id)
  end

  @doc """
  Pin a doc to a home-page slot. With `slot: nil` the lowest free slot
  is taken. Errors: `:pin_limit_reached` (no free slot),
  `{:pin_slot_taken, occupant_slug}` (explicit slot occupied — unpin or
  re-slot the occupant first; no silent displacement), and a plain
  message for the orientation doc, which has its own card.
  """
  def pin(doc, slot \\ nil, actor_user_id \\ nil)

  def pin(%Doc{orientation: true}, _slot, _actor),
    do: {:error, "the orientation doc has its own card on the home page; it can't take a pin slot"}

  def pin(%Doc{} = doc, slot, actor_user_id) when is_nil(slot) or slot in 1..6 do
    taken =
      from(d in base_query(),
        where:
          d.workspace_id == ^doc.workspace_id and not is_nil(d.pin_slot) and
            d.base_doc_id != ^doc.base_doc_id,
        select: {d.pin_slot, d.slug}
      )
      |> Repo.all()
      |> Map.new()

    resolved_slot = slot || Enum.find(1..@pin_limit, &(not Map.has_key?(taken, &1)))

    cond do
      is_nil(resolved_slot) ->
        {:error, :pin_limit_reached}

      occupant = taken[resolved_slot] ->
        {:error, {:pin_slot_taken, resolved_slot, occupant}}

      true ->
        update_pin_slot(doc, resolved_slot, actor_user_id)
    end
  end

  def pin(%Doc{}, _slot, _actor), do: {:error, "pin slot must be between 1 and #{@pin_limit}"}

  @doc "Free a doc's home-page slot. No-op error if it wasn't pinned."
  def unpin(%Doc{pin_slot: nil}, _actor_user_id), do: {:error, "doc is not pinned"}
  def unpin(%Doc{} = doc, actor_user_id), do: update_pin_slot(doc, nil, actor_user_id)

  defp update_pin_slot(%Doc{} = doc, slot, actor_user_id) do
    doc
    |> Ecto.Changeset.change(%{pin_slot: slot})
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        updated = Repo.preload(updated, [:owner, :actor_user])
        Broadcasts.publish_doc_event(:doc_updated, updated)

        Events.record(%{
          workspace_id: updated.workspace_id,
          actor: actor_user_id,
          actor_type: "agent",
          action: if(slot, do: "doc_pinned", else: "doc_unpinned"),
          target_kind: "doc",
          target_id: updated.base_doc_id,
          target_slug: updated.slug,
          target_label: updated.title,
          data: if(slot, do: %{"slot" => slot}, else: %{})
        })

        {:ok, updated}

      err ->
        err
    end
  end

  @doc "The workspace's orientation doc."
  def get_orientation(workspace_id) do
    from(d in base_query(),
      where: d.workspace_id == ^workspace_id and d.orientation,
      preload: [:owner, :actor_user]
    )
    |> Repo.one()
    |> scrub_deleted_tags(workspace_id)
  end

  @doc """
  Seed the default orientation doc into a fresh workspace. The template
  is a form to fill in, not prose — short prompts the team (or their
  agents) replace as conventions emerge.
  """
  def seed_orientation_doc(workspace_id, owner_id) do
    create_doc(%{
      workspace_id: workspace_id,
      owner_id: owner_id,
      actor_user_id: owner_id,
      actor_type: "human",
      orientation: true,
      title: "How we use Aveline here",
      summary:
        "What lives in this workspace and how the team works. Agents fetch this first (aveline get-orientation); humans keep it honest.",
      intent: "seed the workspace orientation doc",
      blocks: Aveline.Workspaces.Template.orientation_blocks()
    })
  end

  @doc """
  Read-time enrichment, never persisted — computed per read so there is
  nothing to keep in sync:

    * doc_link blocks gain a `"target"` map echoing the linked doc's
      current slug/title/summary/state (soft-deleted targets echo their
      latest metadata plus `"deleted" => true`)
    * board blocks gain a `"view"` map — columns (the `by` scope's
      members in creation order) and cards (docs matching the filter
      tags, each with its column)
  """
  def enrich_blocks(blocks, workspace_id) when is_list(blocks) do
    blocks
    |> enrich_doc_links(workspace_id)
    |> Enum.map(fn
      %{"type" => "board"} = b -> Map.put(b, "view", board_view(b, workspace_id))
      b -> b
    end)
  end

  def enrich_blocks(blocks, _workspace_id), do: blocks

  defp board_view(%{"tags" => filter, "by" => scope}, workspace_id) do
    columns = Tags.list_scope_members(workspace_id, scope)

    colors =
      workspace_id
      |> Tags.list_for_workspace()
      |> Enum.filter(&(&1.slug in columns and not is_nil(&1.color)))
      |> Map.new(&{&1.slug, &1.color})

    cards =
      workspace_id
      |> list_current(tags: filter)
      |> Enum.map(fn d ->
        %{
          "slug" => d.slug,
          "title" => d.title,
          "summary" => d.summary,
          "owner" => d.owner && d.owner.username,
          "updated_at" => d.updated_at && DateTime.to_iso8601(d.updated_at),
          # Exclusivity guarantees at most one match.
          "column" => Enum.find(columns, &(&1 in d.tags))
        }
      end)

    %{"columns" => columns, "colors" => colors, "cards" => cards}
  end

  defp board_view(_block, _ws), do: %{"columns" => [], "cards" => []}

  defp enrich_doc_links(blocks, workspace_id) when is_list(blocks) do
    ids =
      for %{"type" => "doc_link", "doc_id" => id} <- blocks,
          is_binary(id),
          uniq: true,
          do: id

    if ids == [] do
      blocks
    else
      live =
        from(d in base_query(),
          where: d.workspace_id == ^workspace_id and d.base_doc_id in ^ids
        )
        |> Repo.all()
        |> Map.new(&{&1.base_doc_id, &1})

      dead =
        case ids -- Map.keys(live) do
          [] ->
            %{}

          missing ->
            from(d in Doc,
              where:
                d.workspace_id == ^workspace_id and d.base_doc_id in ^missing and
                  not d.superseded
            )
            |> Repo.all()
            |> Map.new(&{&1.base_doc_id, &1})
        end

      Enum.map(blocks, fn
        %{"type" => "doc_link", "doc_id" => id} = b ->
          Map.put(b, "target", doc_link_target(live[id], dead[id]))

        b ->
          b
      end)
    end
  end

  defp enrich_doc_links(blocks, _workspace_id), do: blocks

  defp doc_link_target(%Doc{} = live, _dead), do: doc_link_target_map(live, false)
  defp doc_link_target(nil, %Doc{} = dead), do: doc_link_target_map(dead, true)
  # Target vanished entirely (e.g. hard-cleaned in a test DB); render as deleted.
  defp doc_link_target(nil, nil), do: %{"deleted" => true}

  defp doc_link_target_map(%Doc{} = d, deleted?) do
    %{
      "slug" => d.slug,
      "title" => d.title,
      "summary" => d.summary,
      "updated_at" => d.updated_at && DateTime.to_iso8601(d.updated_at),
      "deleted" => deleted?
    }
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
        # Internal-only (workspace seeding) — not exposed through the API.
        orientation: Map.get(attrs, :orientation, false),
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
    ws_id = Map.fetch!(base_attrs, :workspace_id)
    tags = Map.get(base_attrs, :tags, []) || []

    with :ok <- Tags.ensure_all_exist(ws_id, tags),
         :ok <- Tags.ensure_no_scope_conflict(tags),
         {:ok, ops} <- resolve_doc_links(ops, ws_id),
         {:ok, new_blocks} <- run_document_apply([], ops) do
      insert_version(:new, new_blocks, ops, base_attrs, opts)
    end
  end

  def apply_ops(%Doc{} = current, ops, update_attrs, opts)
      when is_list(ops) and is_map(update_attrs) do
    tags = Map.get(update_attrs, :tags, current.tags) || []

    with :ok <- Tags.ensure_all_exist(current.workspace_id, tags),
         :ok <- Tags.ensure_no_scope_conflict(tags),
         {:ok, ops} <- resolve_doc_links(ops, current.workspace_id),
         {:ok, new_blocks} <- run_document_apply(current.blocks || [], ops) do
      insert_version(current, new_blocks, ops, update_attrs, opts)
    end
  end

  # ===== doc_link resolution =====
  # doc_link blocks may arrive with `doc` (a slug) instead of `doc_id`.
  # Resolve slugs against the workspace's current docs and verify every
  # doc_id targets a doc that exists here — before Document.apply_ops, so
  # Block validation only ever sees a canonical doc_id. The stored ops are
  # the resolved ones: version replay stays deterministic even if a slug
  # is later reused.

  defp resolve_doc_links(ops, workspace_id) when is_list(ops) do
    Enum.reduce_while(ops, {:ok, []}, fn op, {:ok, acc} ->
      case resolve_op_doc_link(op, workspace_id) do
        {:ok, resolved} -> {:cont, {:ok, acc ++ [resolved]}}
        err -> {:halt, err}
      end
    end)
  end

  defp resolve_doc_links(ops, _workspace_id), do: {:ok, ops}

  defp resolve_op_doc_link(%{"op" => o, "block" => %{} = block} = op, ws_id)
       when o in ["append_block", "insert_block"] do
    with {:ok, block} <- resolve_block_doc_link(block, ws_id) do
      {:ok, Map.put(op, "block", block)}
    end
  end

  defp resolve_op_doc_link(%{"op" => "modify_block", "patch" => %{} = patch} = op, ws_id) do
    if Map.has_key?(patch, "doc") or Map.has_key?(patch, "doc_id") do
      with {:ok, patch} <- resolve_block_doc_link(patch, ws_id) do
        {:ok, Map.put(op, "patch", patch)}
      end
    else
      {:ok, op}
    end
  end

  defp resolve_op_doc_link(op, _ws_id), do: {:ok, op}

  # Board blocks validate their filter tags at write time (same spirit
  # as doc_link target checks): a board over unknown tags is a typo, not
  # an empty board.
  defp resolve_block_doc_link(%{"type" => "board", "tags" => tags} = block, ws_id)
       when is_list(tags) do
    case Tags.ensure_all_exist(ws_id, Enum.filter(tags, &is_binary/1)) do
      :ok -> {:ok, block}
      err -> err
    end
  end

  defp resolve_block_doc_link(%{"type" => t} = block, _ws_id)
       when is_binary(t) and t != "doc_link",
       do: {:ok, block}

  defp resolve_block_doc_link(%{"doc" => slug} = block, ws_id) when is_binary(slug) do
    case get_current_by_slug(ws_id, slug) do
      nil ->
        {:error, :doc_link_target_not_found, "doc_link target not found in this workspace: #{slug}"}

      %Doc{base_doc_id: base} ->
        {:ok, block |> Map.delete("doc") |> Map.put("doc_id", base)}
    end
  end

  defp resolve_block_doc_link(%{"doc_id" => doc_id} = block, ws_id) when is_binary(doc_id) do
    case Ecto.UUID.cast(doc_id) do
      # Not UUID-shaped: pass through so Block.validate rejects it with the
      # schema error instead of this query raising a CastError.
      :error ->
        {:ok, block}

      {:ok, _} ->
        exists? =
          from(d in base_query(),
            where: d.workspace_id == ^ws_id and d.base_doc_id == ^doc_id,
            select: true,
            limit: 1
          )
          |> Repo.one()

        if exists?,
          do: {:ok, block},
          else: {:error, :doc_link_target_not_found, "doc_link target not found in this workspace: #{doc_id}"}
    end
  end

  defp resolve_block_doc_link(block, _ws_id), do: {:ok, block}

  defp run_document_apply(blocks, ops) do
    case Document.apply_ops(blocks, ops) do
      {:ok, new_blocks} -> {:ok, new_blocks}
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
      |> put_v1_search_text(new_blocks)

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
           resolve_dispositions(current, new_blocks, ops, actor_type, opts) do
      resolves = derive_resolves(dispositions, opts)

      new_attrs = %{
        base_doc_id: current.base_doc_id,
        version_number: current.version_number + 1,
        workspace_id: current.workspace_id,
        slug: current.slug,
        title: Map.get(update_attrs, :title, current.title),
        summary: Map.get(update_attrs, :summary, current.summary),
        tags: Map.get(update_attrs, :tags, current.tags),
        # Slot + orientation carry across edits; neither is editable
        # through apply_ops.
        pin_slot: current.pin_slot,
        orientation: current.orientation,
        owner_id: current.owner_id,
        actor_user_id: Map.fetch!(update_attrs, :actor_user_id),
        actor_type: actor_type,
        blocks: new_blocks,
        operations: ops,
        intent: intent,
        resolves_comment_ids: resolves,
        comment_dispositions: Disposition.to_json(dispositions),
        search_text:
          build_search_text(
            Map.get(update_attrs, :title, current.title),
            Map.get(update_attrs, :summary, current.summary),
            new_blocks
          )
      }

      Multi.new()
      |> Multi.update(
        :supersede,
        Ecto.Changeset.change(current, superseded: true)
      )
      |> Multi.insert(:doc, Doc.changeset(%Doc{}, new_attrs))
      |> Multi.run(:auto_forward_comments, &auto_forward_comments_step/2)
      |> Multi.run(:apply_dispositions, &apply_dispositions_step(&1, &2, dispositions, resolves))
      |> Repo.transaction()
      |> finish_apply()
    end
  end

  # For every live comment on this base doc, insert a new comment-version
  # row pinned to the just-inserted new doc-version. Mark the prior row
  # `superseded` in the same transaction. After this step runs, the
  # "current" row for every base is the new auto-forwarded one — so the
  # disposition step below acts on the new rows (in-place: resolve sets
  # `resolved_at`, reanchor sets `block_id`).
  defp auto_forward_comments_step(repo, %{doc: %Doc{id: new_doc_id, base_doc_id: base_doc_id}}) do
    live =
      from(c in Comment,
        join: d in Doc,
        on: d.id == c.doc_id,
        where:
          d.base_doc_id == ^base_doc_id and
            not c.superseded and
            is_nil(c.deleted_at)
      )
      |> repo.all()

    Enum.reduce_while(live, {:ok, 0}, fn current, {:ok, n} ->
      new_id = Ecto.UUID.generate()

      new_attrs = %{
        "base_comment_id" => current.base_comment_id,
        "version_number" => current.version_number + 1,
        "doc_id" => new_doc_id,
        "block_id" => current.block_id,
        "parent_comment_id" => current.parent_comment_id,
        "body" => current.body,
        "actor_user_id" => current.actor_user_id,
        "actor_type" => current.actor_type,
        "resolved_at" => current.resolved_at,
        "resolved_by_id" => current.resolved_by_id,
        "resolved_by_doc_id" => current.resolved_by_doc_id,
        "edited_at" => current.edited_at
      }

      # Supersede FIRST — the one-current-per-base unique index rejects a
      # second unsuperseded row for the base.
      with {:ok, _} <- repo.update(Ecto.Changeset.change(current, superseded: true)),
           {:ok, _} <-
             repo.insert(Comment.create_changeset(%Comment{id: new_id}, new_attrs)) do
        {:cont, {:ok, n + 1}}
      else
        {:error, err} -> {:halt, {:error, err}}
      end
    end)
  end

  # Validate dispositions. The agent MUST cover every open comment thread
  # whose anchor block was touched by this op set (deleted or modified);
  # threads on untouched blocks and doc-level threads are optional. Humans
  # may submit any subset (or none) and skip the coverage check entirely.
  defp resolve_dispositions(%Doc{} = current, new_blocks, ops, actor_type, opts) do
    raw = Keyword.get(opts, :dispositions, []) || []

    with {:ok, structs} <- cast_all(raw) do
      touched = touched_block_ids(ops)
      deleted = deleted_block_ids(ops)
      open_threads = open_threads_for_base(current.base_doc_id)

      required_ids =
        open_threads
        |> Enum.filter(fn %{block_id: bid} -> bid && MapSet.member?(touched, bid) end)
        |> Enum.map(& &1.id)

      deleted_anchor_ids =
        open_threads
        |> Enum.filter(fn %{block_id: bid} -> bid && MapSet.member?(deleted, bid) end)
        |> Enum.map(& &1.id)

      block_ids = collect_block_ids(new_blocks)

      cond do
        actor_type == "agent" ->
          case Disposition.validate(structs, required_ids, deleted_anchor_ids, block_ids) do
            :ok -> {:ok, structs}
            err -> err
          end

        structs == [] ->
          {:ok, []}

        true ->
          # Humans can dispo partially; only enforce the shape rules (extra
          # dispositions still have to be well-formed reanchors / resolves).
          case Disposition.validate(structs, [], deleted_anchor_ids, block_ids) do
            :ok -> {:ok, structs}
            err -> err
          end
      end
    end
  end

  # Block ids targeted by `delete_block` or `modify_block` in this op set.
  # `append_block` / `insert_block` add new ids; `move_block` only reorders
  # — neither requires the agent to reckon with existing comments.
  defp touched_block_ids(ops) do
    ops
    |> Enum.flat_map(fn
      %{"op" => "delete_block", "id" => id} -> [id]
      %{"op" => "modify_block", "id" => id} -> [id]
      _ -> []
    end)
    |> MapSet.new()
  end

  defp deleted_block_ids(ops) do
    ops
    |> Enum.flat_map(fn
      %{"op" => "delete_block", "id" => id} -> [id]
      _ -> []
    end)
    |> MapSet.new()
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

  # Open (unresolved, not superseded/deleted) top-level threads on this
  # base doc with their current block anchor. Returns LOGICAL ids
  # (`base_comment_id`) since dispositions reference comments by their
  # base id, not a per-version row id.
  defp open_threads_for_base(base_doc_id) do
    from(c in Comment,
      join: d in Doc,
      on: d.id == c.doc_id,
      where:
        d.base_doc_id == ^base_doc_id and
          is_nil(c.parent_comment_id) and
          is_nil(c.resolved_at) and
          is_nil(c.deleted_at) and
          not c.superseded,
      select: %{id: c.base_comment_id, block_id: c.block_id}
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
          where:
            c.base_comment_id in ^leftover and is_nil(c.resolved_at) and
              is_nil(c.deleted_at) and not c.superseded
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

  # ===== Search-text build =====
  # Pre-flatten everything searchable into a single string at write time.
  # The GIN index then indexes `to_tsvector('english', search_text)` so
  # query time is constant regardless of doc length.

  defp put_v1_search_text(attrs, blocks) do
    text =
      build_search_text(
        Map.get(attrs, :title, ""),
        Map.get(attrs, :summary),
        blocks
      )

    Map.put(attrs, :search_text, text)
  end

  # Tags + author already have their own filter rows; the search bar is
  # for finding words inside the doc itself — title, summary, blocks.
  defp build_search_text(title, summary, blocks) do
    [
      to_string(title || ""),
      to_string(summary || ""),
      blocks_to_text(blocks || [])
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp blocks_to_text(blocks) when is_list(blocks) do
    blocks |> Enum.map_join(" ", &block_to_text/1) |> String.trim()
  end

  defp block_to_text(%{"type" => "heading", "text" => text}), do: to_string(text || "")
  defp block_to_text(%{"type" => "code", "content" => content}), do: to_string(content || "")
  defp block_to_text(%{"type" => "paragraph", "content" => spans}), do: spans_to_text(spans)

  defp block_to_text(%{"type" => "list", "items" => items}) when is_list(items) do
    Enum.map_join(items, " ", fn item -> spans_to_text(item["content"]) end)
  end

  defp block_to_text(%{"type" => "table", "headers" => headers, "rows" => rows}) do
    head = headers |> List.wrap() |> Enum.join(" ")

    body =
      rows
      |> List.wrap()
      |> Enum.map_join(" ", fn row ->
        row |> List.wrap() |> Enum.map_join(" ", &spans_to_text/1)
      end)

    [head, body] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
  end

  # Only the note is the doc_link's own content; the target's title is
  # searchable on the target itself.
  defp block_to_text(%{"type" => "doc_link"} = b), do: spans_to_text(b["note"] || [])

  defp block_to_text(_), do: ""

  defp spans_to_text(spans) when is_list(spans) do
    Enum.map_join(spans, "", fn
      %{"text" => t} when is_binary(t) -> t
      _ -> ""
    end)
  end

  defp spans_to_text(_), do: ""

  # ===== Delete / restore =====

  def soft_delete(%Doc{orientation: true}, _deleted_by_id) do
    {:error, :orientation_undeletable}
  end

  def soft_delete(%Doc{} = current, deleted_by_id) do
    current
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(),
      deleted_by_id: deleted_by_id,
      # A deleted doc doesn't hold a home-page slot hostage.
      pin_slot: nil
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
    # The restorable row is a predicate, not a sort: the CHECK constraint
    # guarantees a deleted row is never superseded, so "the deleted row"
    # is unique per base — and its absence means the doc is live (or the
    # base doesn't exist), i.e. not user-deleted.
    deleted_row =
      Repo.one(from d in Doc, where: d.base_doc_id == ^base_doc_id and not is_nil(d.deleted_at))

    case deleted_row do
      nil ->
        exists? =
          Repo.exists?(from d in Doc, where: d.base_doc_id == ^base_doc_id)

        if exists?, do: {:error, :not_user_deleted}, else: {:error, :not_found}

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
