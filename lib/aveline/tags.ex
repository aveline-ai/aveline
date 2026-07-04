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

  def list_for_workspace(workspace_id) when is_binary(workspace_id) do
    from(t in Tag,
      where: t.workspace_id == ^workspace_id,
      order_by: [asc: t.slug]
    )
    |> Repo.all()
  end

  def get(workspace_id, slug) when is_binary(workspace_id) and is_binary(slug) do
    Repo.get_by(Tag, workspace_id: workspace_id, slug: slug)
  end

  def list_slugs(workspace_id) when is_binary(workspace_id) do
    from(t in Tag,
      where: t.workspace_id == ^workspace_id,
      select: t.slug,
      order_by: [asc: t.slug]
    )
    |> Repo.all()
  end

  @doc """
  Tag rows + per-tag stats (current doc count, last-used at). Powers the
  Tags management page.
  """
  def list_with_stats(workspace_id) do
    tags = list_for_workspace(workspace_id)

    docs =
      from(d in Doc,
        where: d.workspace_id == ^workspace_id and is_nil(d.deleted_at),
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

    Enum.map(tags, fn t ->
      s = Map.get(stats, t.slug, %{count: 0, last_used_at: nil})
      Map.merge(%{tag: t}, s)
    end)
    |> Enum.sort_by(fn r -> {-r.count, r.tag.slug} end)
  end

  defp max_dt(nil, b), do: b
  defp max_dt(a, nil), do: a
  defp max_dt(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)

  # ===== Write =====

  def create(workspace_id, slug, description, actor_user_id) do
    case %Tag{}
         |> Tag.create_changeset(%{
           workspace_id: workspace_id,
           slug: slug,
           description: description,
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
  Update a tag's description (and only the description). For renaming,
  use `rename/3` so the cascade across docs happens atomically.
  """
  def update_description(%Tag{} = tag, description, actor_user_id) do
    case tag
         |> Tag.update_changeset(%{slug: tag.slug, description: description})
         |> Repo.update() do
      {:ok, updated} ->
        Events.record(%{
          workspace_id: tag.workspace_id,
          actor: actor_user_id,
          actor_type: "human",
          action: "tag_description_updated",
          target_kind: "tag",
          target_label: tag.slug
        })

        {:ok, updated}

      err ->
        err
    end
  end

  @doc """
  Rename a tag — both the row and every doc carrying its old slug. If
  another tag already owns the new slug, returns
  `{:error, :destination_exists}`. Resolve manually by deleting one of
  the two tags first.
  """
  def rename(%Tag{workspace_id: ws_id, slug: old_slug} = tag, new_slug, actor_user_id) do
    new_slug = new_slug |> to_string() |> String.trim() |> String.downcase()

    cond do
      new_slug == old_slug ->
        {:ok, tag}

      get(ws_id, new_slug) != nil ->
        {:error, :destination_exists}

      true ->
        Repo.transaction(fn ->
          changeset = Tag.update_changeset(tag, %{slug: new_slug, description: tag.description})

          case Repo.update(changeset) do
            {:ok, updated} ->
              affected = cascade_slug_change(ws_id, old_slug, new_slug)

              Events.record(%{
                workspace_id: ws_id,
                actor: actor_user_id,
                actor_type: "human",
                action: "tag_renamed",
                target_kind: "tag",
                target_label: new_slug,
                data: %{"from" => old_slug, "to" => new_slug, "affected" => affected}
              })

              updated

            {:error, cs} ->
              Repo.rollback(cs)
          end
        end)
    end
  end

  @doc """
  Delete a tag. Strips it from every doc that carries it and removes the
  Tag row. Refuses (`{:error, {:would_orphan_docs, count}}`) if any doc's
  only tag is this one — we keep the "every doc has ≥1 tag" invariant
  intact instead of orphaning docs as a side effect of a tag cleanup.
  Audit event records the affected count.
  """
  def delete(%Tag{workspace_id: ws_id, slug: slug} = tag, actor_user_id) do
    case docs_with_only_this_tag_count(ws_id, slug) do
      0 ->
        Repo.transaction(fn ->
          affected = strip_from_docs(ws_id, slug)
          Repo.delete!(tag)

          Events.record(%{
            workspace_id: ws_id,
            actor: actor_user_id,
            actor_type: "human",
            action: "tag_deleted",
            target_kind: "tag",
            target_label: slug,
            data: %{"affected" => affected}
          })

          :ok
        end)

      n when n > 0 ->
        {:error, {:would_orphan_docs, n}}
    end
  end

  @doc """
  Count of (non-deleted) docs in this workspace whose only tag is `slug`.
  Used by the delete flow to surface a blocking message in the UI before
  the user even tries to confirm.
  """
  def docs_with_only_this_tag_count(workspace_id, slug) do
    Repo.one(
      from d in Doc,
        where:
          d.workspace_id == ^workspace_id and
            is_nil(d.deleted_at) and
            d.tags == ^[slug],
        select: count(d.id)
    ) || 0
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
      from(t in Tag, where: t.workspace_id == ^workspace_id and t.slug in ^slugs, select: t.slug)
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
  Members of a scope in creation order — deterministic board columns
  (`status:backlog` before `status:done` because it was created first).
  """
  def list_scope_members(workspace_id, scope) when is_binary(scope) do
    from(t in Tag,
      where: t.workspace_id == ^workspace_id and like(t.slug, ^"#{scope}:%"),
      order_by: [asc: t.inserted_at],
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

  defp strip_from_docs(workspace_id, slug) do
    docs =
      from(d in Doc,
        where: d.workspace_id == ^workspace_id and ^slug in d.tags
      )
      |> Repo.all()

    Enum.each(docs, fn doc ->
      doc
      |> Ecto.Changeset.change(%{tags: List.delete(doc.tags, slug)})
      |> Repo.update!()
    end)

    length(docs)
  end
end
