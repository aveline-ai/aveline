defmodule AvelineWeb.Api.ViewController do
  @moduledoc """
  Views — named, versioned snapshots of the Docs page's display knobs.
  Config tier: create / versioned edit / soft delete / restore, plus
  pin/unpin (placement, in-place). See `Aveline.Views`.
  """
  use AvelineWeb, :controller

  alias Aveline.Views
  alias AvelineWeb.Api.Envelope

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    ws = conn.assigns.current_workspace
    Envelope.ok(conn, %{views: ws.id |> Views.list_for_workspace() |> Enum.map(&Views.safe_map/1)})
  end

  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user
    name = params["name"] |> to_string() |> String.trim() |> String.downcase()

    with {:ok, view} <-
           Views.create(ws.id, name, params["description"], params["config"] || %{}, user.id) do
      Envelope.ok(conn, %{view: Views.safe_map(view)})
    end
  end

  def update(conn, %{"name" => name} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    changes =
      %{}
      |> then(fn c -> if params["new_name"], do: Map.put(c, :name, params["new_name"]), else: c end)
      |> then(fn c ->
        if params["description"], do: Map.put(c, :description, params["description"]), else: c
      end)
      |> then(fn c -> if params["config"], do: Map.put(c, :config, params["config"]), else: c end)

    with %{} = view <- Views.get_current_by_name(ws.id, name) || {:error, :not_found},
         {:ok, view} <- Views.edit(view, changes, user.id) do
      Envelope.ok(conn, %{view: Views.safe_map(view)})
    end
  end

  def delete(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %{} = view <- Views.get_current_by_name(ws.id, name) || {:error, :not_found},
         {:ok, _} <- Views.delete(view, user.id) do
      Envelope.ok(conn, %{})
    end
  end

  def restore(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace

    with {:ok, view} <- Views.restore(ws.id, name) do
      Envelope.ok(conn, %{view: Views.safe_map(view)})
    end
  end

  def pin(conn, %{"name" => name}), do: set_pin(conn, name, true)
  def unpin(conn, %{"name" => name}), do: set_pin(conn, name, false)

  defp set_pin(conn, name, pinned?) do
    ws = conn.assigns.current_workspace

    with %{} = view <- Views.get_current_by_name(ws.id, name) || {:error, :not_found},
         {:ok, view} <- Views.set_pinned(view, pinned?) do
      Envelope.ok(conn, %{view: Views.safe_map(view)})
    end
  end
end
