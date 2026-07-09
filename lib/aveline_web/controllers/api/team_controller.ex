defmodule AvelineWeb.Api.TeamController do
  @moduledoc """
  Workspace member management (list / add / remove) plus the invite
  link. Shares the same `Aveline.Workspaces.*` functions the TeamLive
  uses; same constraints apply (can't self-remove, can't add a user
  twice).
  """
  use AvelineWeb, :controller

  alias Aveline.Workspaces
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    ws = conn.assigns.current_workspace
    members = Workspaces.list_members(ws.id)
    Envelope.ok(conn, %{members: Enum.map(members, &Views.member/1)})
  end

  @doc """
  Add a user by username. Body: `{"username": "..."}`.
  """
  def add(conn, %{"username" => username}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    case Workspaces.add_member_by_username(ws.id, username, user.id) do
      {:ok, _membership, _user} ->
        Envelope.ok(conn, %{})

      {:error, :user_not_found} ->
        {:error, :not_found}

      {:error, :already_member} ->
        {:error, :already_member}

      err ->
        err
    end
  end

  @doc """
  Remove a member. Accepts either a user id (UUID) or a username at the
  `:user_id` path segment — agents tend to know the username from
  `list-members` and shouldn't have to do a second roundtrip to look up
  the UUID. If a non-UUID string is passed, we resolve it as a username.
  """
  def remove(conn, %{"user_id" => user_id_or_username}) do
    ws = conn.assigns.current_workspace
    actor = conn.assigns.current_user

    with {:ok, target_id} <- resolve_user_ref(user_id_or_username) do
      cond do
        target_id == actor.id ->
          {:error, :self_remove}

        true ->
          case Workspaces.remove_member(ws.id, target_id, actor.id) do
            {:ok, _} -> Envelope.ok(conn, %{})
            {:error, :not_found} -> {:error, :not_member}
            {:error, :not_member} -> {:error, :not_member}
            err -> err
          end
      end
    end
  end

  # Distinguish UUID (use as-is) from username (look up).
  defp resolve_user_ref(ref) when is_binary(ref) do
    case Ecto.UUID.cast(ref) do
      {:ok, uuid} ->
        {:ok, uuid}

      :error ->
        case Aveline.Accounts.get_user_by_username(ref) do
          nil -> {:error, :not_member}
          user -> {:ok, user.id}
        end
    end
  end

  @doc """
  Return the workspace's invite URL. Mints one if it doesn't exist.
  Body: `{}`.
  """
  def invite(conn, _params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, invite} <- Workspaces.ensure_invite(ws.id, user.id) do
      Envelope.ok(conn, %{
        code: invite.code,
        url: invite_url(conn, invite.code)
      })
    end
  end

  def revoke_invite(conn, _params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    case Workspaces.get_active_invite_for_workspace(ws.id) do
      nil ->
        Envelope.ok(conn, %{})

      invite ->
        with {:ok, _} <- Workspaces.revoke_invite(invite, user.id) do
          Envelope.ok(conn, %{})
        end
    end
  end

  defp invite_url(_conn, code) do
    AvelineWeb.Endpoint.url() <> "/invite/" <> code
  end
end
