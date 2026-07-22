defmodule Aveline.Events do
  @moduledoc """
  Records and reads workspace-scoped audit events. Self-documenting:
  every mutation across the system funnels through `record/1` so the
  History tab can replay the whole story.

  Callers pass an `attrs` map with at minimum `workspace_id`, `action`,
  and `actor` (a `%User{}` plus optional `actor_type` defaulting to
  "human"). Everything else is optional context.

  Failures here MUST NOT break the originating mutation. We rescue any
  exception and return `:ok` — telemetry should never break the loop.
  """

  import Ecto.Query

  alias Aveline.Accounts.User
  alias Aveline.Events.Event
  alias Aveline.Repo

  @doc """
  Insert one event. `attrs` is a map; required keys: `workspace_id`,
  `action`. Recommended: `actor` (User struct), `actor_type`,
  `target_kind`, `target_id`, `target_slug`, `target_label`, `data`.
  """
  def record(attrs) when is_map(attrs) do
    %Event{}
    |> Ecto.Changeset.change(%{
      workspace_id: attrs[:workspace_id],
      actor_user_id: actor_user_id(attrs[:actor]),
      actor_type: attrs[:actor_type] || "human",
      action: to_string(attrs[:action]),
      target_kind: stringify(attrs[:target_kind]),
      target_id: attrs[:target_id],
      target_slug: stringify(attrs[:target_slug]),
      target_label: stringify(attrs[:target_label]),
      data: attrs[:data] || %{},
      inserted_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    :ok
  rescue
    _ -> :ok
  end

  defp actor_user_id(%User{id: id}), do: id
  defp actor_user_id(id) when is_binary(id), do: id
  defp actor_user_id(_), do: nil

  defp stringify(nil), do: nil
  defp stringify(v) when is_binary(v), do: v
  defp stringify(v), do: to_string(v)

  @doc """
  Cursor-paginated feed for a workspace. Default page size 50, ordered
  newest first. Pass `before: ~U[...]` to fetch the next page, where the
  cursor is the `inserted_at` of the oldest event already shown.

  Cursor-based (not offset) so new events arriving at the top don't shift
  the rest and cause duplicates on the next page.
  """
  def list_for_workspace(workspace_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before = Keyword.get(opts, :before)
    before_id = Keyword.get(opts, :before_id)

    base =
      from e in Event,
        where: e.workspace_id == ^workspace_id,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^limit,
        preload: [:actor_user]

    base
    |> hide_unreadable_doc_events(Keyword.get(opts, :viewer))
    |> apply_before(before)
    |> apply_before_id(before_id)
    |> Repo.all()
  end

  # A private doc's whole event trail vanishes from the feed along with
  # the doc: exclude doc-targeted events whose CURRENT version is
  # private and neither owned by nor shared with the viewer — and
  # comment events too, which carry the doc's title and reference it
  # via data->doc_base_id. Historical events for docs that later went
  # private disappear as well: visibility is evaluated now, not at
  # record time. `viewer: nil` fails closed.
  defp hide_unreadable_doc_events(query, viewer) do
    hidden =
      from d in Aveline.Docs.Doc,
        where: not d.superseded and is_nil(d.deleted_at) and d.visibility == "private",
        select: d.base_doc_id

    hidden =
      case viewer do
        nil ->
          hidden

        user_id ->
          shared =
            from s in Aveline.Docs.Share,
              where: s.user_id == ^user_id and is_nil(s.deleted_at),
              select: s.base_doc_id

          from d in hidden,
            where: d.owner_id != ^user_id and d.base_doc_id not in subquery(shared)
      end

    from e in query,
      where:
        (e.target_kind != "doc" or is_nil(e.target_id) or
           e.target_id not in subquery(hidden)) and
          (e.target_kind != "comment" or
             is_nil(fragment("?->>'doc_base_id'", e.data)) or
             fragment("(?->>'doc_base_id')::uuid", e.data) not in subquery(hidden))
  end

  defp apply_before(q, %DateTime{} = dt), do: from(e in q, where: e.inserted_at < ^dt)
  defp apply_before(q, _), do: q

  defp apply_before_id(q, nil), do: q
  defp apply_before_id(q, ""), do: q

  defp apply_before_id(q, id) when is_binary(id) do
    case Repo.one(from e in Event, where: e.id == ^id, select: e.inserted_at) do
      nil ->
        q

      %DateTime{} = anchor ->
        # Strict less-than on (inserted_at, id) to mirror the ORDER BY
        # so the anchor row itself is excluded and ties don't repeat.
        from e in q,
          where:
            e.inserted_at < ^anchor or
              (e.inserted_at == ^anchor and e.id < ^id)
    end
  end
end
