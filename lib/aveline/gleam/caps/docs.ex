defmodule Aveline.Gleam.Caps.Docs do
  @moduledoc """
  Real IO for src/aveline/caps/docs.gleam. Keep field order in lockstep.

  Coarse caps re-fetch the current doc row by (workspace_id, slug) —
  the same `Docs.get_current_by_slug/2` the handler's access check used
  — and several delegate to the existing `Aveline.Docs` context
  functions so events, broadcasts, and edge behavior stay byte-for-byte
  identical to the pre-Gleam code (the Gleam handler has already
  enforced every product rule; the context re-checks are no-ops).
  Failures handlers don't branch on raise and surface as 500s.
  """

  import Ecto.Query
  import Aveline.Gleam.Interop

  alias Aveline.Docs
  alias Aveline.Repo
  alias AvelineWeb.Api.Views

  def build do
    {:docs_caps,
     fn workspace_id, slug ->
       opt(Docs.get_current_by_slug(workspace_id, slug), &doc_meta/1)
     end,
     fn base_doc_id, user_id ->
       from(s in Aveline.Docs.Share,
         where: s.base_doc_id == ^base_doc_id and s.user_id == ^user_id and is_nil(s.deleted_at),
         select: s.role
       )
       |> Repo.one()
       |> opt(fn
         "editor" -> :editor
         _ -> :viewer
       end)
     end,
     fn workspace_id ->
       workspace_id
       |> Aveline.Workspaces.list_members()
       |> Enum.map(fn m -> {m.user.username, m.user.id} end)
     end,
     fn {:doc_query, workspace_id, viewer, tags, updated, search, sort, owner_ids, limit, offset} ->
       Docs.list_current(workspace_id,
         viewer: viewer,
         tags: tags,
         updated: unopt(updated),
         search: search,
         sort: sort,
         owner_ids: owner_ids,
         limit: limit,
         offset: offset
       )
       |> Enum.map(&Views.doc_summary/1)
     end,
     fn workspace_id, base_doc_id, user_id, source ->
       Aveline.DocViews.record(workspace_id, base_doc_id, user_id, source)
       nil
     end,
     fn workspace_id, slug, viewer ->
       opt(Docs.get_current_by_slug(workspace_id, slug), &full_doc(&1, workspace_id, viewer))
     end,
     fn workspace_id -> opt(Docs.get_orientation(workspace_id), &doc_meta/1) end,
     fn workspace_id, slug, block_id ->
       case Docs.get_current_by_slug(workspace_id, slug) do
         nil ->
           :none

         item ->
           opt(Enum.find(item.blocks || [], &(&1["type"] == "chart" and &1["id"] == block_id)))
       end
     end,
     fn workspace_id, block ->
       case Docs.run_chart(workspace_id, block) do
         %{"error" => msg} -> {:error, msg}
         result -> {:ok, result}
       end
     end,
     fn {:create_attrs, workspace_id, owner_id, actor_user_id, actor_type, title, slug, summary,
         intent, visibility},
        tags,
        blocks ->
       %{
         title: unopt(title),
         slug: unopt(slug),
         summary: unopt(summary),
         tags: tags,
         blocks: blocks,
         workspace_id: workspace_id,
         owner_id: owner_id,
         actor_user_id: actor_user_id,
         actor_type: actor_type,
         intent: unopt(intent),
         visibility: visibility
       }
       |> Docs.create_doc()
       |> write_result()
     end,
     fn workspace_id, slug, blocks, update_attrs ->
       {attrs, opts} = update_args(update_attrs)

       Docs.get_current_by_slug(workspace_id, slug)
       |> Docs.replace_blocks(blocks, attrs, opts)
       |> write_result()
     end,
     fn workspace_id, slug, ops, update_attrs ->
       {attrs, opts} = update_args(update_attrs)

       Docs.get_current_by_slug(workspace_id, slug)
       |> Docs.apply_ops(ops, attrs, opts)
       |> write_result()
     end,
     fn workspace_id, slug, deleted_by_id ->
       doc =
         Docs.get_current_by_slug(workspace_id, slug)
         |> Ecto.Changeset.change(%{
           deleted_at: DateTime.utc_now(),
           deleted_by_id: deleted_by_id,
           # A deleted doc doesn't hold a home-page slot hostage.
           pin_slot: nil
         })
         |> Repo.update!()

       Aveline.Broadcasts.publish_doc_event(:doc_deleted, doc)
       nil
     end,
     fn workspace_id, slug ->
       from(d in Aveline.Docs.Doc,
         where: d.workspace_id == ^workspace_id and d.slug == ^slug,
         order_by: [desc: d.version_number],
         limit: 1
       )
       |> Repo.one()
       |> opt(&doc_meta/1)
     end,
     fn base_doc_id ->
       case Docs.restore(base_doc_id) do
         {:ok, item} -> {:ok, {:restored_doc, item.slug, item.base_doc_id, item.version_number}}
         {:error, :not_user_deleted} -> {:error, :restore_not_user_deleted}
         {:error, :not_found} -> {:error, :restore_not_found}
       end
     end,
     fn workspace_id, base_doc_id ->
       from(d in Docs.base_query(),
         where:
           d.workspace_id == ^workspace_id and not is_nil(d.pin_slot) and
             d.base_doc_id != ^base_doc_id,
         select: {d.pin_slot, d.slug}
       )
       |> Repo.all()
     end,
     fn workspace_id, slug, slot, actor_user_id ->
       current = Docs.get_current_by_slug(workspace_id, slug)

       {:ok, _} =
         case unopt(slot) do
           nil -> Docs.unpin(current, actor_user_id)
           n -> Docs.pin(current, n, actor_user_id)
         end

       nil
     end,
     fn workspace_id, slug, visibility, actor_user_id ->
       {:ok, _} =
         Docs.get_current_by_slug(workspace_id, slug)
         |> Docs.set_visibility(visibility_string(visibility), actor_user_id)

       nil
     end,
     fn base_doc_id ->
       %Aveline.Docs.Doc{base_doc_id: base_doc_id}
       |> Docs.list_shares()
       |> Enum.map(fn s ->
         {:share_info, opt(s.user && s.user.username), s.role,
          opt(s.granted_by && s.granted_by.username), DateTime.to_iso8601(s.inserted_at)}
       end)
     end,
     fn username -> opt(Aveline.Accounts.get_user_by_username(username), & &1.id) end,
     fn workspace_id, user_id -> Aveline.Workspaces.member?(workspace_id, user_id) end,
     fn workspace_id, slug, target_user_id, role, actor_user_id ->
       {:ok, _} =
         Docs.get_current_by_slug(workspace_id, slug)
         |> Docs.share_doc(target_user_id, role, actor_user_id)

       nil
     end,
     fn workspace_id, slug, target_user_id, actor_user_id ->
       {:ok, _} =
         Docs.get_current_by_slug(workspace_id, slug)
         |> Docs.unshare_doc(target_user_id, actor_user_id)

       nil
     end,
     fn base_doc_id ->
       base_doc_id |> Docs.list_versions() |> Enum.map(&Views.doc_version/1)
     end,
     fn workspace_id, base_doc_id, version_number, viewer ->
       opt(
         Docs.get_version(base_doc_id, version_number),
         &full_doc(&1, workspace_id, viewer)
       )
     end}
  end

  def doc_meta(doc) do
    {:doc_meta, doc.id, doc.base_doc_id, doc.slug, doc.title, visibility(doc.visibility),
     doc.owner_id, !!doc.orientation, doc.version_number, opt(doc.pin_slot)}
  end

  defp visibility("private"), do: :private
  defp visibility(_), do: :workspace_visible

  defp visibility_string(:private), do: "private"
  defp visibility_string(:workspace_visible), do: "workspace"

  # Reads return chart CONFIG, not data — enrichment never dials a
  # customer database (agents fetch rows explicitly via run-block).
  defp full_doc(item, workspace_id, viewer) do
    item = %{
      item
      | blocks: Docs.enrich_blocks(item.blocks || [], workspace_id, run_charts: false, viewer: viewer)
    }

    Views.doc_full(item)
  end

  defp write_result({:ok, item}),
    do: {:ok, {:doc_pointer, item.slug, item.base_doc_id, item.id, item.version_number}}

  # Bare-message block/op validation failure — the handler appends the
  # contract hint.
  defp write_result({:error, msg}) when is_binary(msg), do: {:error, {:block_invalid, msg}}

  # Everything else (changesets, disposition tuples, tagged codes) passes
  # through to the FallbackController unchanged.
  defp write_result(other), do: {:error, {:other_failure, other}}

  defp update_args(
         {:update_attrs, actor_user_id, actor_type, title, summary, tags, intent, resolves,
          dispositions}
       ) do
    attrs =
      %{actor_user_id: actor_user_id, actor_type: actor_type}
      |> maybe_put(:title, unopt(title))
      |> maybe_put(:summary, unopt(summary))
      |> maybe_put(:tags, unopt(tags))

    {attrs, [intent: unopt(intent), resolves_comment_ids: resolves, dispositions: dispositions]}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
