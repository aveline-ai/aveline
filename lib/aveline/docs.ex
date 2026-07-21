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
  alias Aveline.Blocks.Block
  alias Aveline.Blocks.Document
  alias Aveline.Comments.Comment
  alias Aveline.Comments.Disposition
  alias Aveline.Docs.Doc
  alias Aveline.Docs.Share
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
    tags = Keyword.get(opts, :tags, []) || []
    owner_ids = Keyword.get(opts, :owner_ids, []) || []
    search = (Keyword.get(opts, :search) || "") |> to_string() |> String.trim()
    # No explicit sort + a search query → relevance; recency otherwise.
    sort = Keyword.get(opts, :sort) || if(search == "", do: :recent, else: :relevance)
    updated = Keyword.get(opts, :updated)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    base =
      from d in base_query(),
        where: d.workspace_id == ^workspace_id

    base
    # `:viewer` is who is asking. Callers must pass it; omitting it
    # fails closed (private docs hidden from everyone).
    |> where_readable(Keyword.get(opts, :viewer))
    |> maybe_filter_tags(tags)
    |> maybe_filter_owners(owner_ids)
    |> maybe_filter_search(search)
    |> maybe_filter_updated(updated)
    |> apply_sort(sort, search)
    |> maybe_select_snippet(search)
    |> maybe_paginate(limit, offset)
    |> Repo.all()
    |> Repo.preload([:owner, :actor_user])
    |> scrub_deleted_tags(workspace_id)
  end

  @doc """
  Normalizes a relative-window token like "7d" or "24h" to its canonical
  string, or nil. Shared by the API and the Docs LiveView so one grammar
  governs the URL param, the view config, and the query. Windows cap at
  365 days — a "recently edited" filter, not an archive query.
  """
  def normalize_within(nil), do: nil

  def normalize_within(v) when is_binary(v) do
    case Regex.run(~r/^(\d{1,4})(h|d)$/, String.trim(v)) do
      [_, n, unit] ->
        n = String.to_integer(n)
        hours = if unit == "d", do: n * 24, else: n
        if hours >= 1 and hours <= 365 * 24, do: "#{n}#{unit}", else: nil

      _ ->
        nil
    end
  end

  def normalize_within(_), do: nil

  # Filters to docs last edited within a relative window — the current
  # version's own timestamp is the last-modified time.
  defp maybe_filter_updated(query, within) do
    case normalize_within(within) do
      nil ->
        query

      token ->
        [_, n, unit] = Regex.run(~r/^(\d+)(h|d)$/, token)
        hours = if unit == "d", do: String.to_integer(n) * 24, else: String.to_integer(n)
        cutoff = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)
        from d in query, where: d.updated_at >= ^cutoff
    end
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
  #   :recent    → updated_at desc (last edited)
  #   :kudos     → kudos count desc, then updated_at desc
  #   :views     → view count desc, then updated_at desc
  #   :relevance → ts_rank against the search query, then updated_at desc
  #                (falls back to :recent when there is no query to rank by)
  # Pins are a home-page concept; they don't influence list ordering.
  defp apply_sort(query, :relevance, ""), do: apply_sort(query, :recent, "")

  defp apply_sort(query, :relevance, q) do
    from d in query,
      order_by: [
        desc:
          fragment(
            "ts_rank(to_tsvector('english', ?), websearch_to_tsquery('english', ?))",
            d.search_text,
            ^q
          ),
        desc: d.updated_at
      ]
  end

  defp apply_sort(query, :recent, _),
    do: from(d in query, order_by: [desc: d.updated_at])

  defp apply_sort(query, :kudos, _), do: count_join_sort(query, "doc_kudos")
  defp apply_sort(query, :views, _), do: count_join_sort(query, "doc_views")

  # A ts_headline extract of why the doc matched. Computed per matching
  # row (the sort may materialize it pre-limit); fine at current corpus
  # sizes — revisit with a lateral-on-limited-rows shape if it shows up
  # in slow queries.
  defp maybe_select_snippet(query, ""), do: query

  defp maybe_select_snippet(query, q) do
    from d in query,
      select_merge: %{
        search_snippet:
          fragment(
            "ts_headline('english', ?, websearch_to_tsquery('english', ?), 'StartSel=**, StopSel=**, MaxFragments=2, MaxWords=12, MinWords=4')",
            d.search_text,
            ^q
          )
      }
  end

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

  # The home page is a team surface; a pinned private doc would leak its
  # title to everyone. set_visibility enforces the reverse direction.
  def pin(%Doc{visibility: "private"}, _slot, _actor),
    do: {:error, "private docs can't be pinned; make the doc workspace-visible first"}

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

  # ===== Visibility & shares =====
  #
  # Doc permissions v1 (doc-permissions TIP): visibility is
  # private | workspace on the doc row; "shared with some people" is
  # private plus doc_shares rows granting specific members access. One
  # access rule, applied here at the read boundary. No admin override:
  # access comes only from visibility, ownership, and shares.

  @visibilities ~w(private workspace)

  def visibilities, do: @visibilities

  @doc """
  Narrows a docs query to what `user_id` may read. `nil` fails closed:
  private docs are visible only through an authenticated viewer.
  """
  def where_readable(query, nil) do
    from d in query, where: d.visibility != "private"
  end

  def where_readable(query, user_id) do
    share_bases =
      from s in Share,
        where: s.user_id == ^user_id and is_nil(s.deleted_at),
        select: s.base_doc_id

    from d in query,
      where:
        d.visibility != "private" or d.owner_id == ^user_id or
          d.base_doc_id in subquery(share_bases)
  end

  @doc "May this workspace member read the doc? (Membership already checked.)"
  def member_can_read?(%Doc{visibility: "private"} = doc, user_id),
    do: doc.owner_id == user_id or share_role(doc.base_doc_id, user_id) != nil

  def member_can_read?(%Doc{}, _user_id), do: true

  @doc "May this workspace member edit the doc? (Membership already checked.)"
  def member_can_edit?(%Doc{visibility: "private"} = doc, user_id),
    do: doc.owner_id == user_id or share_role(doc.base_doc_id, user_id) == "editor"

  def member_can_edit?(%Doc{}, _user_id), do: true

  defp share_role(base_doc_id, user_id) do
    from(s in Share,
      where: s.base_doc_id == ^base_doc_id and s.user_id == ^user_id and is_nil(s.deleted_at),
      select: s.role
    )
    |> Repo.one()
  end

  @doc """
  Change a doc's visibility in place (like pin slots — versioning stays
  about content). Owner only. The orientation doc is permanently public,
  and a pinned doc can't go private: the home page is a team surface and
  a pinned private doc would leak its title there.
  """
  def set_visibility(%Doc{} = doc, visibility, actor_user_id) do
    cond do
      visibility not in @visibilities ->
        {:error, "visibility must be one of: #{Enum.join(@visibilities, ", ")}"}

      doc.orientation ->
        {:error, "the orientation doc is always visible to the whole workspace"}

      doc.owner_id != actor_user_id ->
        {:error, "only the doc's owner can change its visibility"}

      visibility == "private" and not is_nil(doc.pin_slot) ->
        {:error, "unpin this doc first: pinned docs are a team surface and can't be private"}

      doc.visibility == visibility ->
        {:ok, doc}

      true ->
        doc
        |> Ecto.Changeset.change(%{visibility: visibility})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            updated = Repo.preload(updated, [:owner, :actor_user])
            Broadcasts.publish_doc_event(:doc_updated, updated)

            Events.record(%{
              workspace_id: updated.workspace_id,
              actor: actor_user_id,
              actor_type: "agent",
              action: "doc_visibility_changed",
              target_kind: "doc",
              target_id: updated.base_doc_id,
              target_slug: updated.slug,
              target_label: updated.title,
              data: %{"visibility" => visibility}
            })

            {:ok, updated}

          err ->
            err
        end
    end
  end

  @doc "Live shares on a doc, user preloaded, oldest first."
  def list_shares(%Doc{} = doc) do
    from(s in Share,
      where: s.base_doc_id == ^doc.base_doc_id and is_nil(s.deleted_at),
      order_by: [asc: s.inserted_at],
      preload: [:user, :granted_by]
    )
    |> Repo.all()
  end

  @doc """
  Grant (or re-role) a member's access to a doc. Owner only; the target
  must be a member of the doc's workspace. Upserts the live share row.
  """
  def share_doc(%Doc{} = doc, user_id, role, actor_user_id) do
    cond do
      role not in Share.roles() ->
        {:error, "role must be one of: #{Enum.join(Share.roles(), ", ")}"}

      doc.owner_id != actor_user_id ->
        {:error, "only the doc's owner can share it"}

      user_id == doc.owner_id ->
        {:error, "the owner already has full access"}

      not Aveline.Workspaces.member?(doc.workspace_id, user_id) ->
        {:error, "that user is not a member of this workspace"}

      true ->
        existing =
          Repo.one(
            from s in Share,
              where:
                s.base_doc_id == ^doc.base_doc_id and s.user_id == ^user_id and
                  is_nil(s.deleted_at)
          )

        result =
          case existing do
            nil ->
              %Share{}
              |> Share.changeset(%{
                base_doc_id: doc.base_doc_id,
                workspace_id: doc.workspace_id,
                user_id: user_id,
                role: role,
                granted_by_id: actor_user_id
              })
              |> Repo.insert()

            %Share{} = s ->
              s |> Share.changeset(%{role: role}) |> Repo.update()
          end

        with {:ok, share} <- result do
          Events.record(%{
            workspace_id: doc.workspace_id,
            actor: actor_user_id,
            actor_type: "agent",
            action: "doc_shared",
            target_kind: "doc",
            target_id: doc.base_doc_id,
            target_slug: doc.slug,
            target_label: doc.title,
            data: %{"user_id" => user_id, "role" => role}
          })

          {:ok, Repo.preload(share, [:user, :granted_by])}
        end
    end
  end

  @doc "Revoke a member's share. Owner only; soft delete."
  def unshare_doc(%Doc{} = doc, user_id, actor_user_id) do
    with :owner <- if(doc.owner_id == actor_user_id, do: :owner, else: :not_owner),
         %Share{} = share <-
           Repo.one(
             from s in Share,
               where:
                 s.base_doc_id == ^doc.base_doc_id and s.user_id == ^user_id and
                   is_nil(s.deleted_at)
           ) do
      share
      |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now()})
      |> Repo.update()
    else
      :not_owner -> {:error, "only the doc's owner can revoke shares"}
      nil -> {:error, "no live share for that user on this doc"}
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
      current slug/title/summary/tags/state (soft-deleted targets echo
      their latest metadata plus `"deleted" => true`)
    * inline spans whose `"link"` carries a `"doc_id"` gain the same
      echo under `"link" => %{"target" => ...}`
    * chart blocks gain `"source"` and `"result"` echoes. Pass
      `run_charts: false` to skip executing the queries: charts then get
      `"result" => %{"pending" => true}` (source echo and
      missing/deleted-source errors still resolve) so a caller can run
      them async — the doc LiveView does this and streams results in.
  """
  def enrich_blocks(blocks, workspace_id, opts \\ [])

  def enrich_blocks(blocks, workspace_id, opts) when is_list(blocks) do
    run? = Keyword.get(opts, :run_charts, true)

    blocks
    |> enrich_doc_links(workspace_id, Keyword.get(opts, :viewer))
    |> Enum.map(fn
      %{"type" => "chart"} = b -> Map.merge(b, chart_echo(b, workspace_id, run?))
      b -> b
    end)
  end

  def enrich_blocks(blocks, _workspace_id, _opts), do: blocks

  @doc """
  Run a chart block and return its `"result"` map — the async chart
  engine's entry point (doc LiveView `start_async`, run-block API).
  Dispatches on the block shape: a `query_ref` chart (current) resolves
  its catalog query; a legacy inline chart (historical versions) runs
  its stored SQL. Never raises: missing queries, down/deleted sources,
  and bad SQL all come back as `%{"error" => msg}` states.
  """
  def run_chart(workspace_id, %{"query_ref" => ref}) do
    case Aveline.DataSources.Queries.get_current_by_name(workspace_id, ref) do
      nil ->
        %{"error" => "catalog query #{inspect(ref)} not found — it may have been renamed or deleted"}

      %{kind: "derived", name: name} ->
        # Compose the derived query in the engine; its leaves are cached.
        run_catalog(workspace_id, ~s(SELECT * FROM "#{name}"))

      %{kind: "raw", data_source_id: base_id, sql: sql} ->
        run_source(workspace_id, base_id, sql)
    end
  end

  # Legacy inline chart (historical doc versions only).
  def run_chart(workspace_id, %{"data_source_id" => base_id, "query" => sql}) do
    run_source(workspace_id, base_id, sql)
  end

  def run_chart(_workspace_id, _block), do: %{"error" => "invalid chart block"}

  @doc "Bust a chart's cached inputs so its next run re-dials the source."
  def bust_chart(workspace_id, %{"query_ref" => ref}) do
    case Aveline.DataSources.Queries.get_current_by_name(workspace_id, ref) do
      %{kind: "raw", data_source_id: base_id, sql: sql} ->
        Aveline.DataSources.Cache.bust(base_id, sql)

      %{kind: "derived", name: name} ->
        Aveline.DataSources.Catalog.bust_leaves(workspace_id, ~s(SELECT * FROM "#{name}"))

      _ ->
        :ok
    end
  end

  def bust_chart(_workspace_id, %{"data_source_id" => base_id, "query" => sql}),
    do: Aveline.DataSources.Cache.bust(base_id, sql)

  def bust_chart(_workspace_id, _block), do: :ok

  defp run_catalog(workspace_id, sql) do
    case Aveline.DataSources.Catalog.run(workspace_id, sql) do
      {:ok, result} -> result
      {:error, msg} -> %{"error" => msg}
    end
  end

  defp run_source(workspace_id, base_id, sql) do
    case Aveline.DataSources.get_latest_by_base(base_id) do
      %{workspace_id: ^workspace_id, deleted_at: nil, adapter: "workspace"} ->
        run_catalog(workspace_id, sql)

      %{workspace_id: ^workspace_id, deleted_at: nil} = ds ->
        case Aveline.DataSources.Cache.run(ds, sql) do
          {:ok, result} -> result
          {:error, msg} -> %{"error" => msg}
        end

      %{workspace_id: ^workspace_id} ->
        %{"error" => "data source was deleted (credential destroyed); connect a new one and update this block"}

      _ ->
        %{"error" => "data source not found"}
    end
  end

  # Echoes a chart's `source`, `query_sql` (for the SQL tab), and — when
  # run? (the API read path) — its result. A doc read never fails because
  # a query is missing, a source is down, or SQL is wrong; those are all
  # states on the block.
  defp chart_echo(%{"query_ref" => ref} = block, workspace_id, run?) do
    case Aveline.DataSources.Queries.get_current_by_name(workspace_id, ref) do
      nil ->
        %{"result" => %{"error" => "catalog query #{inspect(ref)} not found"}}

      query ->
        result = if run?, do: run_chart(workspace_id, block), else: %{"pending" => true}
        Map.merge(chart_source_echo(workspace_id, query), %{"query_sql" => query.sql, "result" => result})
    end
  end

  # Legacy inline chart echo (historical versions).
  defp chart_echo(%{"data_source_id" => base_id, "query" => sql} = block, workspace_id, run?) do
    case Aveline.DataSources.get_latest_by_base(base_id) do
      %{workspace_id: ^workspace_id, deleted_at: nil} = ds ->
        result = if run?, do: run_chart(workspace_id, block), else: %{"pending" => true}
        %{"source" => Aveline.DataSources.safe_map(ds), "query_sql" => sql, "result" => result}

      %{workspace_id: ^workspace_id} = ds ->
        %{
          "source" => Aveline.DataSources.safe_map(ds),
          "result" => %{
            "error" => "data source was deleted (credential destroyed); connect a new one and update this block"
          }
        }

      _ ->
        %{"result" => %{"error" => "data source not found"}}
    end
  end

  defp chart_echo(_block, _ws, _run?), do: %{"result" => %{"error" => "invalid chart block"}}

  # A raw query's source is its external database; a derived query's
  # source is the workspace catalog.
  defp chart_source_echo(_workspace_id, %{kind: "raw", data_source_id: base_id}) do
    case Aveline.DataSources.get_latest_by_base(base_id) do
      # Source row gone entirely (not just soft-deleted): echo a neutral
      # placeholder so the caption doesn't mislabel a raw chart "derived".
      nil -> %{"source" => %{"name" => "(unknown source)", "adapter" => "sql"}}
      ds -> %{"source" => Aveline.DataSources.safe_map(ds)}
    end
  end

  defp chart_source_echo(workspace_id, %{kind: "derived"}) do
    case Aveline.DataSources.workspace_source(workspace_id) do
      nil -> %{}
      ws_source -> %{"source" => Aveline.DataSources.safe_map(ws_source)}
    end
  end

  defp enrich_doc_links(blocks, workspace_id, viewer) when is_list(blocks) do
    block_ids =
      for %{"type" => "doc_link", "doc_id" => id} <- blocks, is_binary(id), do: id

    span_ids =
      for block <- blocks,
          is_map(block),
          %{"link" => %{"doc_id" => id}} <- all_spans(block),
          is_binary(id),
          do: id

    ids = Enum.uniq(block_ids ++ span_ids)

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

      live_tags = Tags.live_slug_set(workspace_id)

      # Cross-links must not leak what the viewer can't read: a link to
      # a private doc renders as inaccessible (no title, no summary),
      # distinct from deleted. One prefetched share set — no per-link
      # queries. `viewer: nil` fails closed.
      private_ids =
        for {id, d} <- Map.merge(dead, live), d.visibility == "private", do: id

      shared_set =
        if viewer && private_ids != [] do
          from(s in Share,
            where:
              s.user_id == ^viewer and s.base_doc_id in ^private_ids and is_nil(s.deleted_at),
            select: s.base_doc_id
          )
          |> Repo.all()
          |> MapSet.new()
        else
          MapSet.new()
        end

      readable? = fn
        nil -> true
        %Doc{visibility: "private"} = d -> d.owner_id == viewer or MapSet.member?(shared_set, d.base_doc_id)
        %Doc{} -> true
      end

      target_for = fn id ->
        if readable?.(live[id]) and readable?.(dead[id]) do
          doc_link_target(live[id], dead[id], live_tags)
        else
          %{"inaccessible" => true}
        end
      end

      Enum.map(blocks, fn
        %{} = b ->
          b =
            case b do
              %{"type" => "doc_link", "doc_id" => id} ->
                Map.put(b, "target", target_for.(id))

              _ ->
                b
            end

          enrich_span_links(b, target_for)

        b ->
          b
      end)
    end
  end

  defp enrich_doc_links(blocks, _workspace_id, _viewer), do: blocks

  defp enrich_span_links(block, target_for) do
    {:ok, enriched} =
      walk_spans(block, fn
        %{"link" => %{"doc_id" => id} = link} = span when is_binary(id) ->
          {:ok, Map.put(span, "link", Map.put(link, "target", target_for.(id)))}

        span ->
          {:ok, span}
      end)

    enriched
  end

  defp doc_link_target(%Doc{} = live, _dead, live_tags), do: doc_link_target_map(live, false, live_tags)
  defp doc_link_target(nil, %Doc{} = dead, live_tags), do: doc_link_target_map(dead, true, live_tags)
  # Target vanished entirely (e.g. hard-cleaned in a test DB); render as deleted.
  defp doc_link_target(nil, nil, _live_tags), do: %{"deleted" => true}

  defp doc_link_target_map(%Doc{} = d, deleted?, live_tags) do
    %{
      "slug" => d.slug,
      "title" => d.title,
      "summary" => d.summary,
      "tags" => Enum.filter(d.tags || [], &MapSet.member?(live_tags, &1)),
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
        visibility: Map.get(attrs, :visibility) || "workspace",
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

  @doc """
  Ship a new version from a full desired block array (the `--blocks` /
  Write-vs-Edit path), instead of a surgical ops list.

  The caller sends the whole document as it should end up. We compute the
  new block array directly from `desired` (ids preserved where given,
  minted where absent) — the doc stores a full snapshot per version, so
  there's no op replay to reconstruct. Reconciliation is by stable block
  id, never a text diff: a block whose id matches a current block is the
  same block (content updated); an id-less or unknown-id block is new; a
  current id absent from `desired` is deleted. Deterministic — the same
  input always yields the same version.

  We still synthesize an ops list from the (current, new) block sets, but
  only to (a) drive the open-comment disposition gate and (b) leave an
  audit trail. Only `modify_block` / `delete_block` gate on dispositions,
  so the synthetic ops carry exactly the coverage the gate needs.
  """
  def replace_blocks(%Doc{} = current, desired, update_attrs, opts)
      when is_list(desired) and is_map(update_attrs) do
    ws_id = current.workspace_id
    tags = Map.get(update_attrs, :tags, current.tags) || []

    with :ok <- Tags.ensure_all_exist(ws_id, tags),
         :ok <- Tags.ensure_no_scope_conflict(tags),
         {:ok, new_blocks} <- normalize_replacement_blocks(desired, ws_id),
         :ok <- ensure_unique_block_ids(new_blocks) do
      ops = diff_ops(current.blocks || [], new_blocks)
      insert_version(current, new_blocks, ops, update_attrs, opts)
    end
  end

  # Resolve doc_link/chart targets and inline links, then validate + mint
  # ids — one block at a time, halting on the first bad block. Mirrors the
  # per-op path (resolve THEN validate) so `--blocks` and `--ops` accept
  # the exact same block shapes.
  defp normalize_replacement_blocks(desired, ws_id) do
    Enum.reduce_while(desired, {:ok, []}, fn raw, {:ok, acc} ->
      with {:ok, block} <- resolve_block_doc_link(stringify_block(raw), ws_id),
           {:ok, normalized} <- Block.validate(block, mint_id?: true) do
        {:cont, {:ok, acc ++ [normalized]}}
      else
        err -> {:halt, err}
      end
    end)
  end

  defp stringify_block(%{} = block), do: Map.new(block, &stringify_kv/1)
  defp stringify_block(other), do: other

  defp ensure_unique_block_ids(blocks) do
    ids = Enum.map(blocks, & &1["id"])

    case ids -- Enum.uniq(ids) do
      [] -> :ok
      dupes -> {:error, "duplicate block id(s): #{Enum.join(Enum.uniq(dupes), ", ")}"}
    end
  end

  # Derive the audit/gate ops by reconciling current vs new on block id.
  # New blocks -> append_block, changed kept blocks -> modify_block,
  # dropped blocks -> delete_block. Reordered-but-identical blocks emit
  # nothing (moves never gate on dispositions). These ops are stored for
  # the audit trail and read by `resolve_dispositions`; they are NOT
  # replayed (new_blocks is authoritative).
  defp diff_ops(current_blocks, new_blocks) do
    current_by_id = Map.new(current_blocks, &{&1["id"], &1})
    new_ids = MapSet.new(new_blocks, & &1["id"])

    deletes =
      for %{"id" => id} <- current_blocks, not MapSet.member?(new_ids, id) do
        %{"op" => "delete_block", "id" => id}
      end

    changes =
      Enum.flat_map(new_blocks, fn block ->
        case Map.get(current_by_id, block["id"]) do
          nil -> [%{"op" => "append_block", "block" => block}]
          ^block -> []
          _prev -> [%{"op" => "modify_block", "id" => block["id"], "patch" => Map.delete(block, "id")}]
        end
      end)

    deletes ++ changes
  end

  # ===== doc_link resolution =====
  # Links to other docs may arrive with `doc` (a slug) instead of
  # `doc_id` — at the block level (doc_link blocks) and at the span
  # level (link: {doc: slug} inside paragraphs, list items, table cells,
  # doc_link notes). Resolve slugs against the workspace's current docs
  # and verify every doc_id targets a doc that exists here — before
  # Document.apply_ops, so Block validation only ever sees a canonical
  # doc_id. The stored ops are the resolved ones: version replay stays
  # deterministic even if a slug is later reused.

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
    with {:ok, patch} <- resolve_block_doc_link(patch, ws_id) do
      {:ok, Map.put(op, "patch", patch)}
    end
  end

  defp resolve_op_doc_link(op, _ws_id), do: {:ok, op}

  # Works on full blocks and modify_block patches alike: resolve the
  # block-level target (doc_link doc/doc_id, chart source), then every
  # span-level link in whatever span-carrying fields are present.
  defp resolve_block_doc_link(%{} = block, ws_id) do
    with {:ok, block} <- resolve_block_target(block, ws_id) do
      resolve_span_links(block, ws_id)
    end
  end

  # Chart blocks may arrive with `source` (a data source name) instead
  # of `data_source_id`; resolve and verify like doc_link targets.
  defp resolve_block_target(%{"type" => "chart"} = block, ws_id),
    do: resolve_chart_source(block, ws_id)

  defp resolve_block_target(%{"type" => t} = block, _ws_id)
       when is_binary(t) and t != "doc_link",
       do: {:ok, block}

  defp resolve_block_target(%{"doc" => slug} = block, ws_id) when is_binary(slug) do
    case get_current_by_slug(ws_id, slug) do
      nil ->
        {:error, :doc_link_target_not_found, "doc_link target not found in this workspace: #{slug}"}

      %Doc{base_doc_id: base} ->
        {:ok, block |> Map.delete("doc") |> Map.put("doc_id", base)}
    end
  end

  defp resolve_block_target(%{"doc_id" => doc_id} = block, ws_id) when is_binary(doc_id) do
    case Ecto.UUID.cast(doc_id) do
      # Not UUID-shaped: pass through so Block.validate rejects it with the
      # schema error instead of this query raising a CastError.
      :error ->
        {:ok, block}

      {:ok, _} ->
        if doc_exists?(ws_id, doc_id),
          do: {:ok, block},
          else: {:error, :doc_link_target_not_found, "doc_link target not found in this workspace: #{doc_id}"}
    end
  end

  # Typeless modify_block patches: `query_ref` is the chart key
  # (doc_link patches use `doc`/`doc_id` and match above).
  defp resolve_block_target(%{"query_ref" => ref} = patch, ws_id) when is_binary(ref),
    do: resolve_chart_source(patch, ws_id)

  defp resolve_block_target(block, _ws_id), do: {:ok, block}

  # A chart references a catalog query by name; verify it resolves (like
  # a doc_link target). The query owns the SQL and the source, so the
  # block carries nothing else.
  defp resolve_chart_source(%{"query_ref" => ref} = block, ws_id) when is_binary(ref) do
    case Aveline.DataSources.Queries.get_current_by_name(ws_id, String.downcase(ref)) do
      nil ->
        {:error, :query_not_found,
         "no catalog query named #{inspect(ref)} — create it first (aveline create-query), then chart it"}

      _query ->
        {:ok, block}
    end
  end

  defp resolve_chart_source(block, _ws_id), do: {:ok, block}

  defp resolve_span_links(%{} = block, ws_id) do
    walk_spans(block, fn
      # href alongside doc/doc_id: leave untouched so Inline validation
      # rejects it with the shape error instead of silently dropping one.
      %{"link" => %{"href" => _}} = span ->
        {:ok, span}

      %{"link" => %{"doc" => slug} = _link} = span when is_binary(slug) ->
        case get_current_by_slug(ws_id, slug) do
          nil ->
            {:error, :doc_link_target_not_found, "link target not found in this workspace: #{slug}"}

          %Doc{base_doc_id: base} ->
            {:ok, Map.put(span, "link", %{"doc_id" => base})}
        end

      %{"link" => %{"doc_id" => doc_id}} = span when is_binary(doc_id) ->
        case Ecto.UUID.cast(doc_id) do
          # Not UUID-shaped: pass through for Inline's schema error.
          :error ->
            {:ok, span}

          {:ok, _} ->
            if doc_exists?(ws_id, doc_id),
              do: {:ok, span},
              else: {:error, :doc_link_target_not_found, "link target not found in this workspace: #{doc_id}"}
        end

      span ->
        {:ok, span}
    end)
  end

  defp doc_exists?(ws_id, base_doc_id) do
    from(d in base_query(),
      where: d.workspace_id == ^ws_id and d.base_doc_id == ^base_doc_id,
      select: true,
      limit: 1
    )
    |> Repo.one()
    |> Kernel.==(true)
  end

  # ===== span walking =====
  # Applies fun to every inline span in the map's span-carrying fields —
  # "content" (paragraph), "note" (doc_link), "items" (list), "rows"
  # (table) — threading {:ok, _} | error. Only keys present are walked,
  # so it works on modify_block patches too. Malformed shapes pass
  # through untouched; Block.validate rejects them with the schema error.

  defp walk_spans(%{} = map, fun) do
    Enum.reduce_while(~w(content note items rows), {:ok, map}, fn key, {:ok, acc} ->
      case Map.get(acc, key) do
        nil ->
          {:cont, {:ok, acc}}

        val ->
          case walk_spans_in(key, val, fun) do
            {:ok, new} -> {:cont, {:ok, Map.put(acc, key, new)}}
            err -> {:halt, err}
          end
      end
    end)
  end

  defp walk_spans_in(key, spans, fun) when key in ~w(content note) and is_list(spans),
    do: map_while_ok(spans, fun)

  defp walk_spans_in("items", items, fun) when is_list(items) do
    map_while_ok(items, fn
      %{"content" => spans} = item when is_list(spans) ->
        with {:ok, new} <- map_while_ok(spans, fun), do: {:ok, Map.put(item, "content", new)}

      other ->
        {:ok, other}
    end)
  end

  defp walk_spans_in("rows", rows, fun) when is_list(rows) do
    map_while_ok(rows, fn
      row when is_list(row) ->
        map_while_ok(row, fn
          cell when is_list(cell) -> map_while_ok(cell, fun)
          other -> {:ok, other}
        end)

      other ->
        {:ok, other}
    end)
  end

  defp walk_spans_in(_key, val, _fun), do: {:ok, val}

  defp map_while_ok(list, fun) do
    Enum.reduce_while(list, {:ok, []}, fn el, {:ok, acc} ->
      case fun.(el) do
        {:ok, new} -> {:cont, {:ok, [new | acc]}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  # Every inline span in the block, flattened — for collecting link ids.
  defp all_spans(%{} = block) do
    content = if is_list(block["content"]), do: block["content"], else: []
    note = if is_list(block["note"]), do: block["note"], else: []

    items =
      for %{"content" => c} <- List.wrap(block["items"]), is_list(c), span <- c, do: span

    cells =
      for row <- List.wrap(block["rows"]),
          is_list(row),
          cell <- row,
          is_list(cell),
          span <- cell,
          do: span

    content ++ note ++ items ++ cells
  end

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
        # Slot, orientation, and visibility carry across edits; none is
        # editable through apply_ops (visibility changes go through
        # set_visibility, in place on the current row).
        pin_slot: current.pin_slot,
        orientation: current.orientation,
        visibility: current.visibility,
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
