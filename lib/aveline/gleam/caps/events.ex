defmodule Aveline.Gleam.Caps.Events do
  @moduledoc "Real IO for src/aveline/caps/events.gleam. Keep field order in lockstep (`record` FIRST)."

  import Aveline.Gleam.Interop

  alias Aveline.Events

  def build do
    {:events_caps,
     fn {:event_attrs, workspace_id, actor, actor_type, action, target_kind, target_id,
         target_slug, target_label} ->
       Events.record(%{
         workspace_id: workspace_id,
         actor: actor,
         actor_type: Atom.to_string(actor_type),
         action: action,
         target_kind: target_kind,
         target_id: target_id,
         target_slug: unopt(target_slug),
         target_label: unopt(target_label)
       })

       nil
     end,
     fn workspace_id, {:event_query, limit, before_id, viewer} ->
       opts = [limit: limit, viewer: viewer] ++ before_opt(before_id)

       workspace_id
       |> Events.list_for_workspace(opts)
       |> Enum.map(&event_row/1)
     end}
  end

  defp before_opt(:none), do: []
  defp before_opt({:some, id}), do: [before_id: id]

  defp event_row(e) do
    {:event_row, e.id, opt(e.action), opt(e.target_kind), opt(e.target_id), opt(e.target_slug),
     opt(e.target_label), opt(e.actor_type), opt(e.actor_user, &user_info/1), e.data || %{},
     DateTime.to_iso8601(e.inserted_at)}
  end

  defp user_info(u), do: {:user_info, u.id, u.username, opt(u.display_name), opt(u.email)}
end
