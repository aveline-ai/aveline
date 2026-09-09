defmodule AvelineWeb.Api.MilestoneController do
  @moduledoc """
  Timeline milestones — dated workspace facts that overlay time-series
  charts as vertical markers. Create one from a deploy pipeline and
  every chart spanning that date annotates itself.

  Thin adapter: all decision logic lives in the Gleam handler
  (src/aveline/handlers/milestones.gleam).
  """
  use AvelineWeb, :controller

  import Aveline.Gleam.Interop, only: [unopt: 1]

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    milestones = :aveline@handlers@milestones.index(CtxBuilder.build(), CtxBuilder.scope(conn))
    Envelope.ok(conn, %{milestones: Enum.map(milestones, &wire/1)})
  end

  def create(conn, params) do
    request =
      {:create_request, str(params["name"]), opt_str(params["date"]),
       opt_str(params["description"])}

    case :aveline@handlers@milestones.create(CtxBuilder.build(), CtxBuilder.scope(conn), request) do
      {:ok, milestone} -> Envelope.ok(conn, %{milestone: wire(milestone)})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  def delete(conn, %{"id" => id}) do
    case :aveline@handlers@milestones.delete(CtxBuilder.build(), CtxBuilder.scope(conn), id) do
      {:ok, deleted_id} -> Envelope.ok(conn, %{deleted: deleted_id})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  # The wire shape chart specs and the API both echo (was Milestones.safe_map/1).
  defp wire({:milestone, id, name, date, description, created_at}) do
    %{
      "id" => id,
      "name" => name,
      "date" => date,
      "description" => unopt(description),
      "created_at" => created_at
    }
  end

  defp str(v) when is_binary(v), do: v
  defp str(_), do: ""

  defp opt_str(v) when is_binary(v), do: {:some, v}
  defp opt_str(_), do: :none
end
