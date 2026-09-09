defmodule AvelineWeb.Api.TeamController do
  @moduledoc """
  Workspace member management (list / add / remove) plus the invite
  link. All decision logic lives in the Gleam handler
  (src/aveline/handlers/team.gleam); this module is the thin
  params -> handler -> envelope adapter. Same constraints as before
  (can't self-remove, can't add a user twice).
  """
  use AvelineWeb, :controller

  import Aveline.Gleam.Interop, only: [unopt: 1]

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    members = :aveline@handlers@team.list(CtxBuilder.build(), CtxBuilder.scope(conn))
    Envelope.ok(conn, %{members: Enum.map(members, &member_json/1)})
  end

  @doc """
  Add a user by username. Body: `{"username": "..."}`.
  """
  def add(conn, %{"username" => username}) when is_binary(username) do
    case :aveline@handlers@team.add(CtxBuilder.build(), CtxBuilder.scope(conn), username) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  # Non-binary username — same :user_not_found -> 404 as before.
  def add(_conn, %{"username" => _}), do: {:error, :not_found}

  @doc """
  Remove a member. Accepts either a user id (UUID) or a username at the
  `:user_id` path segment — agents tend to know the username from
  `list-members` and shouldn't have to do a second roundtrip to look up
  the UUID. If a non-UUID string is passed, we resolve it as a username.
  """
  def remove(conn, %{"user_id" => user_id_or_username}) do
    case :aveline@handlers@team.remove(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           user_id_or_username
         ) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  @doc """
  Return the workspace's invite URL. Mints one if it doesn't exist.
  Body: `{}`.
  """
  def invite(conn, _params) do
    case :aveline@handlers@team.invite(CtxBuilder.build(), CtxBuilder.scope(conn)) do
      {:ok, {:invite_response, code, url}} -> Envelope.ok(conn, %{code: code, url: url})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  def revoke_invite(conn, _params) do
    case :aveline@handlers@team.revoke_invite(CtxBuilder.build(), CtxBuilder.scope(conn)) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  defp member_json({:member, {:team_user, id, username, display_name, email}, role, joined_at}) do
    %{
      "id" => id,
      "username" => username,
      "display_name" => unopt(display_name),
      "email" => unopt(email),
      "role" => role,
      "joined_at" => joined_at
    }
  end
end
