defmodule Aveline.DocViews do
  @moduledoc """
  Records "doc read" events. Used by both the web LV mount and the API
  doc-show controller, so popularity reflects both human and agent reads.
  """

  import Ecto.Query

  alias Aveline.Docs.Doc
  alias Aveline.DocViews.DocView
  alias Aveline.Events
  alias Aveline.Repo

  # A view by the same user on the same doc within this window is treated
  # as the same "functional" view and is NOT recorded. Refresh / back-and-
  # forth / re-opening a tab mid-task doesn't pollute counts. After the
  # window elapses, the user is presumed to be coming back deliberately
  # and the next read is recorded.
  @dedup_window_minutes 60

  @doc """
  Insert a view row. `actor_type` is "human" or "agent".

  No-op (returns `:ok`) when:
    * a required key is missing — never break a doc render over telemetry
    * the same user already viewed this doc within `@dedup_window_minutes`

  This keeps every popularity / count query a plain `COUNT(*)` — no
  windowing or deduping in read paths.
  """
  def record(workspace_id, base_doc_id, user_id, actor_type)
      when is_binary(workspace_id) and is_binary(base_doc_id) and
             is_binary(user_id) and actor_type in ["human", "agent"] do
    if recent_view?(base_doc_id, user_id) do
      :ok
    else
      Repo.insert!(%DocView{
        workspace_id: workspace_id,
        base_doc_id: base_doc_id,
        user_id: user_id,
        actor_type: actor_type,
        viewed_at: DateTime.utc_now()
      })

      log_view_event(workspace_id, base_doc_id, user_id, actor_type)
      :ok
    end
  rescue
    _ -> :ok
  end

  def record(_, _, _, _), do: :ok

  defp log_view_event(workspace_id, base_doc_id, user_id, actor_type) do
    doc =
      from(d in Doc,
        where: d.base_doc_id == ^base_doc_id and is_nil(d.deleted_at),
        limit: 1
      )
      |> Repo.one()

    Events.record(%{
      workspace_id: workspace_id,
      actor: user_id,
      actor_type: actor_type,
      action: "doc_viewed",
      target_kind: "doc",
      target_id: base_doc_id,
      target_slug: doc && doc.slug,
      target_label: doc && doc.title
    })
  end

  defp recent_view?(base_doc_id, user_id) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@dedup_window_minutes * 60, :second)

    from(v in DocView,
      where:
        v.base_doc_id == ^base_doc_id and
          v.user_id == ^user_id and
          v.viewed_at > ^cutoff,
      select: 1,
      limit: 1
    )
    |> Repo.one() != nil
  end

  @doc """
  The last `limit` distinct docs this user opened in this workspace,
  most recent first — human views only, so an agent reading half the
  wiki over the API under your token doesn't swamp your own trail.
  Joined to the current live doc row, so deleted docs drop out. Powers
  the Home "Jump back in" shelf.

  Returns `{doc, last_viewed_at}` tuples.
  """
  def recent_for_user(workspace_id, user_id, limit \\ 3) do
    latest =
      from(v in DocView,
        where:
          v.workspace_id == ^workspace_id and v.user_id == ^user_id and
            v.actor_type == "human",
        group_by: v.base_doc_id,
        select: %{base_doc_id: v.base_doc_id, last_viewed_at: max(v.viewed_at)}
      )

    from(l in subquery(latest),
      join: d in Doc,
      on: d.base_doc_id == l.base_doc_id and is_nil(d.deleted_at),
      where: d.workspace_id == ^workspace_id,
      order_by: [desc: l.last_viewed_at],
      limit: ^limit,
      select: {d, l.last_viewed_at}
    )
    |> Repo.all()
  end

  @doc """
  Has this user's agent ever read this doc? Powers the onboarding
  page's setup detection: `get-orientation` records an agent view, so
  an agent view of the orientation doc means the CLI is installed,
  authed, and oriented.
  """
  def agent_viewed?(base_doc_id, user_id) do
    from(v in DocView,
      where:
        v.base_doc_id == ^base_doc_id and v.user_id == ^user_id and
          v.actor_type == "agent",
      select: 1,
      limit: 1
    )
    |> Repo.one() != nil
  end

  @doc """
  Total view count for a logical doc.
  """
  def count_for_base(base_doc_id) when is_binary(base_doc_id) do
    from(v in DocView, where: v.base_doc_id == ^base_doc_id, select: count(v.id))
    |> Repo.one()
  end

  @doc """
  Bulk-fetch view counts for a list of base_doc_ids. Returns a map of
  base_doc_id => count. Missing ids get 0 via Map.get default. Single
  round-trip, used by the workspace card list to avoid N+1.
  """
  def counts_by_base([]), do: %{}

  def counts_by_base(base_doc_ids) when is_list(base_doc_ids) do
    from(v in DocView,
      where: v.base_doc_id in ^base_doc_ids,
      group_by: v.base_doc_id,
      select: {v.base_doc_id, count(v.id)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
