defmodule Aveline.Tags do
  @moduledoc """
  Workspace-scoped tag taxonomy. Tags are first-class entities with
  required descriptions so an LLM can scan the index and pick the right
  one to filter on. Doc rows still carry `docs.tags[]` (string array of
  slugs); this module owns the lifecycle of the slugs themselves.
  """

  import Ecto.Query

  alias Aveline.Docs.Doc
  alias Aveline.Events
  alias Aveline.Repo
  alias Aveline.Tags.Tag

  # ===== Read =====
  # All reads are LIVE-only: a soft-deleted tag is invisible everywhere
  # (lists, filters, board columns, doc tag arrays) until restored.

  # Live = neither superseded (an edit made a newer version) nor
  # user-deleted. The partial unique index matches this predicate.
  def base_query do
    from t in Tag, where: not t.superseded and is_nil(t.deleted_at)
  end

  # The one tag ordering, used by every surface: alphabetical by slug
  # unless a tag carries a sort_key override.
  def list_for_workspace(workspace_id) when is_binary(workspace_id) do
    from(t in base_query(),
      where: t.workspace_id == ^workspace_id,
      order_by: [asc: fragment("COALESCE(?, ?)", t.sort_key, t.slug), asc: t.slug]
    )
    |> Repo.all()
  end

  def get(workspace_id, slug) when is_binary(workspace_id) and is_binary(slug) do
    from(t in base_query(), where: t.workspace_id == ^workspace_id and t.slug == ^slug)
    |> Repo.one()
  end

  @doc """
  The user-deleted row for a slug — the restore target. A predicate,
  not a sort: superseded rows are history, never restorable.
  """
  def get_deleted(workspace_id, slug) when is_binary(workspace_id) and is_binary(slug) do
    from(t in Tag,
      where:
        t.workspace_id == ^workspace_id and t.slug == ^slug and
          not is_nil(t.deleted_at)
    )
    |> Repo.one()
  end

  def list_slugs(workspace_id) when is_binary(workspace_id) do
    from(t in base_query(),
      where: t.workspace_id == ^workspace_id,
      select: t.slug,
      order_by: [asc: fragment("COALESCE(?, ?)", t.sort_key, t.slug), asc: t.slug]
    )
    |> Repo.all()
  end

  @doc "Live tag slugs as a set — used to scrub deleted tags from doc reads."
  def live_slug_set(workspace_id) do
    workspace_id |> list_slugs() |> MapSet.new()
  end

  @doc """
  Tag rows + per-tag stats (current doc count, last-used at). Powers the
  Tags management page.
  """
  def list_with_stats(workspace_id) do
    tags = list_for_workspace(workspace_id)

    docs =
      from(d in Doc,
        where: d.workspace_id == ^workspace_id and not d.superseded and is_nil(d.deleted_at),
        select: %{tags: d.tags, updated_at: d.updated_at}
      )
      |> Repo.all()

    stats =
      Enum.reduce(docs, %{}, fn %{tags: tags, updated_at: ts}, acc ->
        Enum.reduce(tags, acc, fn slug, inner ->
          Map.update(inner, slug, %{count: 1, last_used_at: ts}, fn agg ->
            %{
              count: agg.count + 1,
              last_used_at: max_dt(agg.last_used_at, ts)
            }
          end)
        end)
      end)

    # Keep the workspace tag order (sort_key override, alphabetical
    # otherwise) — one ordering on every surface.
    Enum.map(tags, fn t ->
      s = Map.get(stats, t.slug, %{count: 0, last_used_at: nil})
      Map.merge(%{tag: t}, s)
    end)
  end

  defp max_dt(nil, b), do: b
  defp max_dt(a, nil), do: a
  defp max_dt(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)

  # ===== Write =====

  def create(workspace_id, slug, description, actor_user_id, opts \\ []) do
    id = Ecto.UUID.generate()

    case %Tag{id: id}
         |> Tag.create_changeset(%{
           workspace_id: workspace_id,
           base_tag_id: id,
           version_number: 1,
           slug: slug,
           description: description,
           color: Keyword.get(opts, :color),
           sort_key: Keyword.get(opts, :sort_key),
           created_by_id: actor_user_id
         })
         |> Repo.insert() do
      {:ok, tag} ->
        Events.record(%{
          workspace_id: workspace_id,
          actor: actor_user_id,
          actor_type: "human",
          action: "tag_created",
          target_kind: "tag",
          target_label: tag.slug,
          data: %{"description" => tag.description}
        })

        {:ok, tag}

      err ->
        err
    end
  end

  @doc """
  Edit a tag — rename, redescribe, and/or recolor. Every edit inserts a
  NEW VERSION row sharing `base_tag_id` (the prior row is superseded),
  so tag history is first-class like doc history. Renames additionally
  cascade the slug across every doc carrying it, atomically — docs keep
  the tag through the rename.

  `changes` keys: `:slug`, `:description`, `:color`, `:sort_key`
  (`:color` and `:sort_key` accept nil to clear). Returns
  `{:error, :destination_exists}` if a rename targets a slug another
  live tag owns.
  """
  def edit(%Tag{} = tag, changes, actor_user_id) when is_map(changes) do
    new_slug =
      changes |> Map.get(:slug, tag.slug) |> to_string() |> String.trim() |> String.downcase()

    new_description = Map.get(changes, :description, tag.description)
    new_color = if Map.has_key?(changes, :color), do: changes.color, else: tag.color
    new_sort_key = if Map.has_key?(changes, :sort_key), do: changes.sort_key, else: tag.sort_key

    cond do
      {new_slug, new_description, new_color, new_sort_key} ==
          {tag.slug, tag.description, tag.color, tag.sort_key} ->
        {:ok, tag}

      new_slug != tag.slug and get(tag.workspace_id, new_slug) != nil ->
        {:error, :destination_exists}

      true ->
        insert_tag_version(tag, new_slug, new_description, new_color, new_sort_key, actor_user_id)
    end
  end

  defp insert_tag_version(%Tag{} = current, slug, description, color, sort_key, actor_user_id) do
    renamed? = slug != current.slug

    Repo.transaction(fn ->
      # Supersede the current row FIRST — mechanism, not deletion; the
      # one-current-per-base index rejects a second unsuperseded row.
      {:ok, _} = current |> Ecto.Changeset.change(%{superseded: true}) |> Repo.update()

      changeset =
        %Tag{id: Ecto.UUID.generate()}
        |> Tag.create_changeset(%{
          workspace_id: current.workspace_id,
          base_tag_id: current.base_tag_id,
          version_number: current.version_number + 1,
          slug: slug,
          description: description,
          color: color,
          sort_key: sort_key,
          created_by_id: actor_user_id
        })

      case Repo.insert(changeset) do
        {:ok, updated} ->
          affected =
            if renamed?, do: cascade_slug_change(current.workspace_id, current.slug, slug), else: 0

          Events.record(%{
            workspace_id: current.workspace_id,
            actor: actor_user_id,
            actor_type: "human",
            action: if(renamed?, do: "tag_renamed", else: "tag_updated"),
            target_kind: "tag",
            target_label: slug,
            data:
              %{"version" => updated.version_number}
              |> then(fn d ->
                if renamed?,
                  do: Map.merge(d, %{"from" => current.slug, "to" => slug, "affected" => affected}),
                  else: d
              end)
          })

          updated

        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
  end

  @doc "Rename a tag (compat shim over edit/3)."
  def rename(%Tag{} = tag, new_slug, actor_user_id),
    do: edit(tag, %{slug: new_slug}, actor_user_id)

  @doc "Update a tag's description (compat shim over edit/3)."
  def update_description(%Tag{} = tag, description, actor_user_id),
    do: edit(tag, %{description: description}, actor_user_id)

  @doc """
  Soft-delete a tag. Doc rows KEEP the slug in their tags array — the
  tag simply turns invisible to every current read (lists, filters,
  board columns, doc tag arrays) until restored, making delete and
  restore perfect inverses. No cascade touches any doc.
  """
  def delete(%Tag{workspace_id: ws_id, slug: slug} = tag, actor_user_id) do
    tag
    |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(), deleted_by_id: actor_user_id})
    |> Repo.update()
    |> case do
      {:ok, deleted} ->
        Events.record(%{
          workspace_id: ws_id,
          actor: actor_user_id,
          actor_type: "human",
          action: "tag_deleted",
          target_kind: "tag",
          target_label: slug
        })

        {:ok, deleted}

      err ->
        err
    end
  end

  @doc """
  Restore a soft-deleted tag: every doc that carried it shows it again
  instantly (the attachments never left). Errors with `:slug_taken` if a
  live tag reclaimed the slug in the meantime.
  """
  def restore(%Tag{deleted_at: nil}, _actor_user_id), do: {:error, "tag is not deleted"}

  def restore(%Tag{superseded: true}, _actor_user_id),
    do: {:error, "tag row was superseded by a newer version, not user-deleted"}

  def restore(%Tag{workspace_id: ws_id, slug: slug} = tag, actor_user_id) do
    if get(ws_id, slug) do
      {:error, :slug_taken}
    else
      tag
      |> Ecto.Changeset.change(%{deleted_at: nil, deleted_by_id: nil})
      |> Repo.update()
      |> case do
        {:ok, restored} ->
          Events.record(%{
            workspace_id: ws_id,
            actor: actor_user_id,
            actor_type: "human",
            action: "tag_restored",
            target_kind: "tag",
            target_label: slug
          })

          {:ok, restored}

        err ->
          err
      end
    end
  end

  # ===== Validation hook called from Docs.apply_ops =====

  @doc """
  Ensure every slug in `slugs` already exists as a Tag row in this
  workspace. Returns `:ok` or `{:error, {:unknown_tags, [slug, …]}}`.
  Empty tag list is OK.
  """
  def ensure_all_exist(_workspace_id, []), do: :ok

  def ensure_all_exist(workspace_id, slugs) when is_list(slugs) do
    existing =
      from(t in base_query(),
        where: t.workspace_id == ^workspace_id and t.slug in ^slugs,
        select: t.slug
      )
      |> Repo.all()
      |> MapSet.new()

    missing = slugs |> Enum.uniq() |> Enum.reject(&MapSet.member?(existing, &1))

    if missing == [], do: :ok, else: {:error, {:unknown_tags, missing}}
  end

  # ===== Scoped tags =====
  # A tag slug of the form `scope:value` (e.g. `status:todo`) is an enum
  # member: a doc's tag set may carry at most one tag per scope. Plain
  # tags are unaffected. The scope lives in the slug — no extra state.

  @doc ~S(The scope of a scoped tag — "status" for "status:todo"; nil for plain tags.)
  def scope_of(slug) when is_binary(slug) do
    case String.split(slug, ":", parts: 2) do
      [scope, _value] -> scope
      _ -> nil
    end
  end

  def scope_of(_), do: nil

  @doc ~S(The value of a scoped tag — "todo" for "status:todo"; the slug itself for plain tags.)
  def value_of(slug) when is_binary(slug) do
    case String.split(slug, ":", parts: 2) do
      [_scope, value] -> value
      _ -> slug
    end
  end

  @doc """
  Scoped-tag exclusivity: at most one tag per scope in a tag set.
  Pure — runs on the doc write path next to `ensure_all_exist/2`.
  """
  def ensure_no_scope_conflict(slugs) when is_list(slugs) do
    slugs
    |> Enum.group_by(&scope_of/1)
    |> Map.delete(nil)
    |> Enum.find(fn {_scope, tags} -> length(Enum.uniq(tags)) > 1 end)
    |> case do
      nil -> :ok
      {scope, tags} -> {:error, {:tag_scope_conflict, scope, Enum.sort(Enum.uniq(tags))}}
    end
  end

  @doc """
  Members of a scope in the workspace tag order (sort_key override,
  alphabetical otherwise) — the same ordering every tag surface uses,
  so board columns match the glossary.
  """
  def list_scope_members(workspace_id, scope) when is_binary(scope) do
    from(t in base_query(),
      where: t.workspace_id == ^workspace_id and like(t.slug, ^"#{scope}:%"),
      order_by: [asc: fragment("COALESCE(?, ?)", t.sort_key, t.slug), asc: t.slug],
      select: t.slug
    )
    |> Repo.all()
  end

  # ===== Internal cascade helpers =====

  # Walk every doc carrying `old_slug` and replace it with `new_slug` in
  # the tags array (preserving order, deduplicating).
  defp cascade_slug_change(workspace_id, old_slug, new_slug) do
    docs =
      from(d in Doc,
        where: d.workspace_id == ^workspace_id and ^old_slug in d.tags
      )
      |> Repo.all()

    Enum.each(docs, fn doc ->
      new_tags =
        doc.tags
        |> Enum.map(fn t -> if t == old_slug, do: new_slug, else: t end)
        |> Enum.uniq()

      doc
      |> Ecto.Changeset.change(%{tags: new_tags})
      |> Repo.update!()
    end)

    length(docs)
  end
end
