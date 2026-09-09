defmodule AvelineWeb.Api.EventController do
  @moduledoc """
  Workspace activity feed. Same `Aveline.Events.list_for_workspace`
  the ActivityLive uses, paginated. Limit parsing and response assembly
  live in src/aveline/handlers/events.gleam; the listing SQL is one
  coarse cap.
  """
  use AvelineWeb, :controller

  import Aveline.Gleam.Interop, only: [unopt: 1]

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, params) do
    {:events_response, events, next_before_id} =
      :aveline@handlers@events.index(
        CtxBuilder.build(),
        CtxBuilder.scope(conn),
        limit_param(params["limit"]),
        opt_binary(params["before_id"])
      )

    Envelope.ok(conn, %{
      events: Enum.map(events, &event_map/1),
      # If a `before_id` cursor is needed for next page, agents pass
      # the oldest id from this batch in `before_id`.
      next_before_id: unopt(next_before_id)
    })
  end

  defp limit_param(v) when is_binary(v), do: {:some, v}
  defp limit_param(v) when is_integer(v), do: {:some, Integer.to_string(v)}
  defp limit_param(_), do: :none

  defp opt_binary(v) when is_binary(v), do: {:some, v}
  defp opt_binary(_), do: :none

  defp event_map(
         {:event_row, id, action, target_kind, target_id, target_slug, target_label, actor_type,
          actor_user, data, occurred_at}
       ) do
    %{
      "id" => id,
      "action" => unopt(action),
      "target_kind" => unopt(target_kind),
      "target_id" => unopt(target_id),
      "target_slug" => unopt(target_slug),
      "target_label" => unopt(target_label),
      "actor" => %{"type" => unopt(actor_type), "user" => user_map(actor_user)},
      "data" => data,
      "occurred_at" => occurred_at
    }
  end

  defp user_map(:none), do: nil

  defp user_map({:some, {:user_info, id, username, display_name, email}}) do
    %{
      "id" => id,
      "username" => username,
      "display_name" => unopt(display_name),
      "email" => unopt(email)
    }
  end
end
