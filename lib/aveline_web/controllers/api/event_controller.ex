defmodule AvelineWeb.Api.EventController do
  @moduledoc """
  Workspace activity feed. Same `Aveline.Events.list_for_workspace`
  the ActivityLive uses, paginated.
  """
  use AvelineWeb, :controller

  alias Aveline.Events
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, params) do
    ws = conn.assigns.current_workspace

    opts =
      [
        limit: parse_limit(params["limit"]),
        before_id: params["before_id"]
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    events = Events.list_for_workspace(ws.id, opts)

    Envelope.ok(conn, %{
      events: Enum.map(events, &Views.event/1),
      # If a `before_id` cursor is needed for next page, agents pass
      # the oldest id from this batch in `before_id`.
      next_before_id:
        case List.last(events) do
          nil -> nil
          e -> e.id
        end
    })
  end

  defp parse_limit(nil), do: 50
  defp parse_limit(""), do: 50

  defp parse_limit(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n > 0 and n <= 200 -> n
      _ -> 50
    end
  end

  defp parse_limit(n) when is_integer(n) and n > 0 and n <= 200, do: n
  defp parse_limit(_), do: 50
end
