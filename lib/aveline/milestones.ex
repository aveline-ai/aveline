defmodule Aveline.Milestones do
  @moduledoc """
  Timeline milestones — dated workspace facts (a release shipped, a
  pricing change, a migration) that annotate every time-series chart
  whose x-range spans them. A milestone is data, not chart config:
  recorded once, drawn everywhere, maintained in one place. Deploy
  pipelines create them via `aveline create-milestone`.

  Soft-delete only, no version chain: edits are typo fixes on a dated
  fact, not history. (Named "milestone", not "event": `list-events` is
  the workspace activity feed.)
  """

  import Ecto.Query

  alias Aveline.Milestones.Milestone
  alias Aveline.Repo

  def list_active(workspace_id) do
    from(m in Milestone,
      where: m.workspace_id == ^workspace_id and is_nil(m.deleted_at),
      order_by: [asc: m.date, asc: m.inserted_at]
    )
    |> Repo.all()
  end

  def create(workspace_id, attrs, user_id) do
    %Milestone{}
    |> Milestone.changeset(
      Map.merge(attrs, %{workspace_id: workspace_id, created_by_id: user_id})
    )
    |> Repo.insert()
  end

  def delete(workspace_id, id, user_id) do
    case Repo.one(
           from(m in Milestone,
             where: m.id == ^id and m.workspace_id == ^workspace_id and is_nil(m.deleted_at)
           )
         ) do
      nil ->
        {:error, :not_found}

      milestone ->
        milestone
        |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(), deleted_by_id: user_id})
        |> Repo.update()
    end
  end

  @doc "The wire shape chart specs and the API both echo."
  def safe_map(%Milestone{} = m) do
    %{
      "id" => m.id,
      "name" => m.name,
      "date" => Date.to_iso8601(m.date),
      "description" => m.description,
      "created_at" => DateTime.to_iso8601(m.inserted_at)
    }
  end
end
