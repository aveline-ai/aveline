defmodule Aveline.Gleam.Caps.Milestones do
  @moduledoc "Real IO for src/aveline/caps/milestones.gleam. Keep field order in lockstep."

  import Aveline.Gleam.Interop
  import Ecto.Query

  alias Aveline.Milestones.Milestone
  alias Aveline.Repo

  def build do
    {:milestones_caps,
     fn workspace_id ->
       workspace_id
       |> Aveline.Milestones.list_active()
       |> Enum.map(&to_gleam/1)
     end,
     fn {:new_milestone, workspace_id, name, date_iso, description, created_by} ->
       %Milestone{}
       |> Ecto.Changeset.change(%{
         workspace_id: workspace_id,
         name: name,
         date: Date.from_iso8601!(date_iso),
         description: unopt(description),
         created_by_id: created_by
       })
       |> Repo.insert!()
       |> to_gleam()
     end,
     fn workspace_id, id ->
       Repo.one(
         from(m in Milestone,
           where: m.id == ^id and m.workspace_id == ^workspace_id and is_nil(m.deleted_at)
         )
       )
       |> opt(& &1.id)
     end,
     fn milestone_id, user_id ->
       Repo.get!(Milestone, milestone_id)
       |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(), deleted_by_id: user_id})
       |> Repo.update!()

       nil
     end}
  end

  defp to_gleam(%Milestone{} = m) do
    {:milestone, m.id, m.name, Date.to_iso8601(m.date), opt(m.description),
     DateTime.to_iso8601(m.inserted_at)}
  end
end
