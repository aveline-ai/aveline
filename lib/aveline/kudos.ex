defmodule Aveline.Kudos do
  @moduledoc """
  Per-user "thanks" markers on logical docs. One row per (user, base_doc).
  Toggling deletes if present, inserts if absent. Used both for the
  in-doc affirmation UI and as a popularity signal for sorting.
  """

  import Ecto.Query

  alias Aveline.Docs.Doc
  alias Aveline.Events
  alias Aveline.Kudos.Kudos, as: Mark
  alias Aveline.Repo

  @doc """
  Toggle a kudos for (user, base_doc). Returns `{:ok, :given}` or
  `{:ok, :revoked}`. The workspace_id is required for indexing/scoping.
  """
  def toggle(workspace_id, base_doc_id, user_id)
      when is_binary(workspace_id) and is_binary(base_doc_id) and is_binary(user_id) do
    result =
      case Repo.get_by(Mark, base_doc_id: base_doc_id, user_id: user_id) do
        nil ->
          %Mark{}
          |> Ecto.Changeset.change(%{
            workspace_id: workspace_id,
            base_doc_id: base_doc_id,
            user_id: user_id,
            given_at: DateTime.utc_now()
          })
          |> Repo.insert!()

          :given

        %Mark{} = existing ->
          Repo.delete!(existing)
          :revoked
      end

    log_kudos_event(workspace_id, base_doc_id, user_id, result)
    {:ok, result}
  end

  defp log_kudos_event(workspace_id, base_doc_id, user_id, result) do
    doc =
      from(d in Doc,
        where: d.base_doc_id == ^base_doc_id and is_nil(d.deleted_at),
        limit: 1
      )
      |> Repo.one()

    Events.record(%{
      workspace_id: workspace_id,
      actor: user_id,
      actor_type: "human",
      action: if(result == :given, do: "kudos_given", else: "kudos_revoked"),
      target_kind: "doc",
      target_id: base_doc_id,
      target_slug: doc && doc.slug,
      target_label: doc && doc.title
    })
  end

  def count_for_base(base_doc_id) when is_binary(base_doc_id) do
    from(k in Mark, where: k.base_doc_id == ^base_doc_id, select: count(k.id))
    |> Repo.one()
  end

  def given_by?(base_doc_id, user_id) when is_binary(base_doc_id) and is_binary(user_id) do
    from(k in Mark,
      where: k.base_doc_id == ^base_doc_id and k.user_id == ^user_id,
      select: 1,
      limit: 1
    )
    |> Repo.one() != nil
  end

  def given_by?(_, _), do: false

  @doc """
  Bulk kudos counts for a list of base_doc_ids. Returns base_doc_id => count.
  """
  def counts_by_base([]), do: %{}

  def counts_by_base(base_doc_ids) when is_list(base_doc_ids) do
    from(k in Mark,
      where: k.base_doc_id in ^base_doc_ids,
      group_by: k.base_doc_id,
      select: {k.base_doc_id, count(k.id)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
