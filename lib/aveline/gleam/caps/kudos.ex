defmodule Aveline.Gleam.Caps.Kudos do
  @moduledoc "Real IO for src/aveline/caps/kudos.gleam. Keep field order in lockstep."

  import Aveline.Gleam.Interop

  alias Aveline.Kudos.Kudos, as: Mark
  alias Aveline.Repo

  def build do
    {:kudos_caps,
     fn base_doc_id, user_id ->
       Repo.get_by(Mark, base_doc_id: base_doc_id, user_id: user_id)
       |> opt(& &1.id)
     end,
     fn workspace_id, base_doc_id, user_id ->
       %Mark{}
       |> Ecto.Changeset.change(%{
         workspace_id: workspace_id,
         base_doc_id: base_doc_id,
         user_id: user_id,
         given_at: DateTime.utc_now()
       })
       |> Repo.insert!()

       nil
     end,
     fn mark_id ->
       Repo.delete!(Repo.get!(Mark, mark_id))
       nil
     end,
     fn base_doc_id -> Aveline.Kudos.count_for_base(base_doc_id) end}
  end
end
