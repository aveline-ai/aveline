defmodule AvelineWeb.Api.MilestoneController do
  @moduledoc """
  Timeline milestones — dated workspace facts that overlay time-series
  charts as vertical markers. Create one from a deploy pipeline and
  every chart spanning that date annotates itself.
  """
  use AvelineWeb, :controller

  alias Aveline.Milestones
  alias AvelineWeb.Api.Envelope

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    ws = conn.assigns.current_workspace
    Envelope.ok(conn, %{milestones: Enum.map(Milestones.list_active(ws.id), &Milestones.safe_map/1)})
  end

  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    attrs = %{
      name: params["name"] || "",
      date: params["date"],
      description: params["description"]
    }

    with {:ok, milestone} <- Milestones.create(ws.id, attrs, user.id) do
      Envelope.ok(conn, %{milestone: Milestones.safe_map(milestone)})
    end
  end

  def delete(conn, %{"id" => id}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, _} <- Milestones.delete(ws.id, id, user.id) do
      Envelope.ok(conn, %{deleted: id})
    end
  end
end
