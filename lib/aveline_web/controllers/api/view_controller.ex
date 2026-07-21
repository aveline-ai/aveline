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
    user = conn.assigns.current_user

    Envelope.ok(conn, %{
      views:
        ws.id
        |> Views.list_for_workspace(viewer: user.id)
        |> Enum.map(&Views.safe_map/1)
    })
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

    with {:ok, view} <- fetch_usable(ws, user, name),
         :ok <- ensure_view_editable(view, user),
         {:ok, view} <- Views.edit(view, changes, user.id) do
      Envelope.ok(conn, %{view: Views.safe_map(view)})
    end
  end

  def delete(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, view} <- fetch_usable(ws, user, name),
         :ok <- ensure_view_editable(view, user),
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
    user = conn.assigns.current_user

    with {:ok, view} <- fetch_usable(ws, user, name),
         {:ok, view} <- Views.set_pinned(view, pinned?) do
      Envelope.ok(conn, %{view: Views.safe_map(view)})
    end
  end

  # ===== Visibility & shares (the doc model copied onto views) =====

  @doc "Change a view's visibility in place: private | workspace. Owner only."
  def set_visibility(conn, %{"name" => name, "visibility" => vis}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, view} <- fetch_usable(ws, user, name),
         {:ok, view} <- Views.set_visibility(view, vis, user.id) do
      Envelope.ok(conn, %{name: view.name, visibility: view.visibility})
    end
  end

  def set_visibility(_conn, _params), do: {:error, {:missing_field, "visibility"}}

  @doc "Grant a member access to a private view. Owner only."
  def share(conn, %{"name" => name, "username" => username} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, view} <- fetch_usable(ws, user, name),
         %_{} = target <- Aveline.Accounts.get_user_by_username(username) || {:error, :not_member},
         {:ok, share} <- Views.share_view(view, target.id, params["role"] || "viewer", user.id) do
      Envelope.ok(conn, %{name: view.name, username: username, role: share.role})
    end
  end

  def share(_conn, _params), do: {:error, {:missing_field, "username"}}

  @doc "Revoke a member's share. Owner only."
  def unshare(conn, %{"name" => name, "username" => username}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, view} <- fetch_usable(ws, user, name),
         %_{} = target <- Aveline.Accounts.get_user_by_username(username) || {:error, :not_member},
         {:ok, _} <- Views.unshare_view(view, target.id, user.id) do
      Envelope.ok(conn, %{name: view.name, username: username})
    end
  end

  def unshare(_conn, _params), do: {:error, {:missing_field, "username"}}

  @doc "Live shares on a view."
  def shares(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, view} <- fetch_usable(ws, user, name) do
      shares =
        Enum.map(Views.list_shares(view), fn s ->
          %{
            username: s.user && s.user.username,
            role: s.role,
            granted_by: s.granted_by && s.granted_by.username,
            granted_at: s.inserted_at
          }
        end)

      Envelope.ok(conn, %{name: view.name, visibility: view.visibility, shares: shares})
    end
  end

  # ===== Helpers =====

  # One access rule for every by-name endpoint; inaccessible and
  # nonexistent are indistinguishable on purpose.
  defp fetch_usable(ws, user, name) do
    case Views.get_current_by_name(ws.id, name) do
      nil -> {:error, :not_found}
      view -> if Views.member_can_use?(view, user.id), do: {:ok, view}, else: {:error, :not_found}
    end
  end

  defp ensure_view_editable(view, user) do
    if Views.member_can_edit?(view, user.id),
      do: :ok,
      else: {:error, :forbidden, "You have viewer access to this view; editing needs an editor share or ownership."}
  end
end
