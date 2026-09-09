defmodule Aveline.Gleam.Caps.Workspaces do
  @moduledoc "Real IO for src/aveline/caps/workspaces.gleam. Keep field order in lockstep."

  import Aveline.Gleam.Interop

  alias Aveline.Workspaces

  def build do
    {:workspaces_caps,
     fn user_id ->
       user_id |> Workspaces.list_for_user() |> Enum.map(&info/1)
     end,
     fn slug ->
       slug |> Workspaces.get_active_by_slug() |> opt(&info/1)
     end,
     fn workspace_id, user_id ->
       Workspaces.member?(workspace_id, user_id)
     end,
     fn name, slug, creator_id ->
       # Full furnishing (template tags/docs, built-in source) rides along
       # inside create_workspace. Gleam pre-validates name + slug, so the
       # only product-behavior failure left is the slug unique constraint.
       case Workspaces.create_workspace(%{
              "name" => name,
              "slug" => slug,
              "created_by_id" => creator_id
            }) do
         {:ok, ws} ->
           {:ok, info(ws)}

         {:error, %Ecto.Changeset{errors: errors} = cs} ->
           if slug_taken?(errors[:slug]) do
             {:error, :slug_taken}
           else
             raise "unexpected workspace changeset failure: #{inspect(cs.errors)}"
           end
       end
     end,
     fn workspace_id, user_id ->
       {:ok, _} = Workspaces.ensure_member(workspace_id, user_id)
       nil
     end}
  end

  defp slug_taken?({_msg, opts}), do: Keyword.get(opts, :constraint) == :unique
  defp slug_taken?(_), do: false

  defp info(ws), do: {:workspace_info, ws.id, ws.slug, ws.name, DateTime.to_iso8601(ws.inserted_at)}
end
