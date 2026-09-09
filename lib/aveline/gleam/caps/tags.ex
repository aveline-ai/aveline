defmodule Aveline.Gleam.Caps.Tags do
  @moduledoc """
  Real IO for src/aveline/caps/tags.gleam. Keep field order in lockstep.

  The handler owns validation (slugs arrive pre-validated via
  aveline/tags/rules), so the changesets here only fail on the partial
  unique index — that one maps to `{:error, nil}` (product behavior:
  slug_taken); anything else raises and surfaces as a 500.
  """

  import Aveline.Gleam.Interop
  import Ecto.Query

  alias Aveline.Docs.Doc
  alias Aveline.Events
  alias Aveline.Repo
  alias Aveline.Tags
  alias Aveline.Tags.Tag

  def build do
    {:tags_caps,
     fn workspace_id, slug -> Tags.get(workspace_id, slug) |> opt(&to_gleam/1) end,
     fn workspace_id, slug -> Tags.get_deleted(workspace_id, slug) |> opt(&to_gleam/1) end,
     fn workspace_id ->
       workspace_id
       |> Tags.list_with_stats()
       |> Enum.map(fn %{tag: t, count: count, last_used_at: last} ->
         {:tag_stats, to_gleam(t), count, opt(last, &DateTime.to_iso8601/1)}
       end)
     end,
     fn workspace_id, fields, actor_user_id -> insert(workspace_id, fields, actor_user_id) end,
     fn current, fields, actor_user_id -> insert_version(current, fields, actor_user_id) end,
     fn tag_id, actor_user_id ->
       Repo.get!(Tag, tag_id)
       |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(), deleted_by_id: actor_user_id})
       |> Repo.update!()

       nil
     end,
     fn tag_id ->
       Repo.get!(Tag, tag_id)
       |> Ecto.Changeset.change(%{deleted_at: nil, deleted_by_id: nil})
       |> Repo.update!()

       nil
     end,
     fn workspace_id, actor_user_id, event -> record_event(workspace_id, actor_user_id, event) end}
  end

  # ===== Writes =====

  defp insert(workspace_id, {:tag_fields, slug, description, color, sort_key}, actor_user_id) do
    id = Ecto.UUID.generate()

    %Tag{id: id}
    |> Tag.create_changeset(%{
      workspace_id: workspace_id,
      base_tag_id: id,
      version_number: 1,
      slug: slug,
      description: description,
      color: unopt(color),
      sort_key: unopt(sort_key),
      created_by_id: actor_user_id
    })
    |> Repo.insert()
    |> case do
      {:ok, tag} -> {:ok, to_gleam(tag)}
      {:error, cs} -> slug_conflict_or_raise(cs)
    end
  end

  defp insert_version({:tag, id, _, _, _, _, _, _, _, _}, {:tag_fields, slug, description, color, sort_key}, actor_user_id) do
    current = Repo.get!(Tag, id)
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
          color: unopt(color),
          sort_key: unopt(sort_key),
          created_by_id: actor_user_id
        })

      case Repo.insert(changeset) do
        {:ok, updated} ->
          affected =
            if renamed?, do: cascade_slug_change(current.workspace_id, current.slug, slug), else: 0

          {updated, affected}

        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
    |> case do
      {:ok, {updated, affected}} -> {:ok, {to_gleam(updated), affected}}
      {:error, cs} -> slug_conflict_or_raise(cs)
    end
  end

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

  defp slug_conflict_or_raise(%Ecto.Changeset{errors: errors} = cs) do
    # The composite unique index reports on :workspace_id (first field
    # of the unique_constraint), so match any unique-constraint error.
    unique? =
      Enum.any?(errors, fn
        {_field, {_msg, opts}} -> Keyword.get(opts, :constraint) == :unique
        _ -> false
      end)

    if unique? do
      {:error, nil}
    else
      raise "unexpected tag changeset failure (handler should have validated): #{inspect(cs.errors)}"
    end
  end

  # ===== Events =====

  defp record_event(workspace_id, actor_user_id, event) do
    {action, label, data} =
      case event do
        {:tag_created, slug, description} ->
          {"tag_created", slug, %{"description" => description}}

        {:tag_updated, slug, version} ->
          {"tag_updated", slug, %{"version" => version}}

        {:tag_renamed, from, to, version, affected} ->
          {"tag_renamed", to, %{"version" => version, "from" => from, "to" => to, "affected" => affected}}

        {:tag_deleted, slug} ->
          {"tag_deleted", slug, nil}

        {:tag_restored, slug} ->
          {"tag_restored", slug, nil}
      end

    attrs = %{
      workspace_id: workspace_id,
      actor: actor_user_id,
      actor_type: "human",
      action: action,
      target_kind: "tag",
      target_label: label
    }

    Events.record(if data, do: Map.put(attrs, :data, data), else: attrs)
    nil
  end

  # ===== Conversion =====

  defp to_gleam(%Tag{} = t) do
    {:tag, t.id, t.base_tag_id, t.version_number, t.slug, t.description, opt(t.color),
     opt(t.sort_key), t.superseded, DateTime.to_iso8601(t.inserted_at)}
  end
end
