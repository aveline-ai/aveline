defmodule Aveline.Stats do
  @moduledoc """
  Workspace-scoped aggregations for the Stats page. Two reads:

    * `workspace_totals/1` — big-number summary of what the workspace has
      collectively produced and absorbed (docs, reads, kudos, comments,
      …). Goal: make the value of using Aveline tangible.

    * `contributors/1` — per-member breakdown of work made + impact
      earned (reads + kudos on docs they own). Goal: surface the people
      keeping the wiki alive so being a good maintainer feels seen.

  Every aggregation is a plain `count` / `sum` against existing tables —
  no new schema. N+1 per-user queries are fine at v0 scale (one workspace
  with a handful of members). Optimize when we have a workspace where
  this matters.
  """

  import Ecto.Query

  alias Aveline.Docs.Doc
  alias Aveline.DocViews.DocView
  alias Aveline.Comments.Comment
  alias Aveline.Kudos.Kudos, as: KudosMark
  alias Aveline.Repo
  alias Aveline.Tags.Tag
  alias Aveline.Workspaces

  # ===== Workspace totals =====

  def workspace_totals(workspace_id) when is_binary(workspace_id) do
    %{
      active_docs: count_active_docs(workspace_id),
      total_edits: count_total_versions(workspace_id),
      reads: count_reads(workspace_id),
      kudos: count_kudos(workspace_id),
      comments: count_comments(workspace_id),
      tags: count_tags(workspace_id),
      members: length(Workspaces.list_members(workspace_id))
    }
  end

  defp count_active_docs(ws_id) do
    Repo.aggregate(
      from(d in Doc, where: d.workspace_id == ^ws_id and not d.superseded and is_nil(d.deleted_at)),
      :count,
      :id
    )
  end

  # Every doc row is one version, so total rows ≈ total edits + creates.
  defp count_total_versions(ws_id) do
    Repo.aggregate(from(d in Doc, where: d.workspace_id == ^ws_id), :count, :id)
  end

  defp count_reads(ws_id) do
    Repo.aggregate(from(v in DocView, where: v.workspace_id == ^ws_id), :count, :id)
  end

  defp count_kudos(ws_id) do
    Repo.aggregate(from(k in KudosMark, where: k.workspace_id == ^ws_id), :count, :id)
  end

  defp count_comments(ws_id) do
    from(c in Comment,
      join: d in Doc,
      on: d.id == c.doc_id,
      where: d.workspace_id == ^ws_id and is_nil(c.deleted_at)
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_tags(ws_id) do
    Repo.aggregate(from(t in Tag, where: t.workspace_id == ^ws_id), :count, :id)
  end

  # ===== Contributors =====

  @doc """
  Per-member breakdown, ranked by docs-owned then kudos-earned. Surfaces
  who's been writing + maintaining the corpus.
  """
  def contributors(workspace_id) when is_binary(workspace_id) do
    members = Workspaces.list_members(workspace_id)

    members
    |> Enum.map(fn m -> build_contributor_row(workspace_id, m.user) end)
    |> Enum.sort_by(fn s -> {-s.docs_owned, -s.kudos_earned, -s.reads_earned, s.user.username} end)
  end

  defp build_contributor_row(ws_id, user) do
    owned_base_ids = owned_base_doc_ids(ws_id, user.id)

    %{
      user: user,
      docs_owned: length(owned_base_ids),
      edits_made: count_user_versions(ws_id, user.id),
      reads_earned: count_views_for_base_ids(owned_base_ids),
      kudos_earned: count_kudos_for_base_ids(owned_base_ids),
      kudos_given: count_user_kudos_given(ws_id, user.id),
      comments_posted: count_user_comments(ws_id, user.id)
    }
  end

  defp owned_base_doc_ids(ws_id, user_id) do
    from(d in Doc,
      where:
        d.workspace_id == ^ws_id and d.owner_id == ^user_id and not d.superseded and
          is_nil(d.deleted_at),
      select: d.base_doc_id
    )
    |> Repo.all()
  end

  # Counts every version this user authored — captures total *editing
  # activity*, including v1 (creating).
  defp count_user_versions(ws_id, user_id) do
    Repo.aggregate(
      from(d in Doc, where: d.workspace_id == ^ws_id and d.actor_user_id == ^user_id),
      :count,
      :id
    )
  end

  defp count_views_for_base_ids([]), do: 0

  defp count_views_for_base_ids(base_ids) do
    Repo.aggregate(
      from(v in DocView, where: v.base_doc_id in ^base_ids),
      :count,
      :id
    )
  end

  defp count_kudos_for_base_ids([]), do: 0

  defp count_kudos_for_base_ids(base_ids) do
    Repo.aggregate(
      from(k in KudosMark, where: k.base_doc_id in ^base_ids),
      :count,
      :id
    )
  end

  defp count_user_kudos_given(ws_id, user_id) do
    Repo.aggregate(
      from(k in KudosMark, where: k.workspace_id == ^ws_id and k.user_id == ^user_id),
      :count,
      :id
    )
  end

  defp count_user_comments(ws_id, user_id) do
    from(c in Comment,
      join: d in Doc,
      on: d.id == c.doc_id,
      where:
        d.workspace_id == ^ws_id and c.actor_user_id == ^user_id and is_nil(c.deleted_at)
    )
    |> Repo.aggregate(:count, :id)
  end
end
