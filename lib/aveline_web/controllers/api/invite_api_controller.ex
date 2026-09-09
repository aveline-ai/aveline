defmodule AvelineWeb.Api.InviteApiController do
  @moduledoc """
  JSON backing for the Elm invite landing page (fe-auth). Mirrors
  InviteLive:

    * `GET /papi/invites/:code` — resolve the invite. Works signed-out
      (the page shows a signup form) and signed-in (`already_member`
      tells Elm to bounce straight into the workspace).
    * `POST /papi/invites/:code/accept` — signed-in "Join {workspace}"
      confirm. Idempotent membership add.
  """
  use AvelineWeb, :controller

  alias Aveline.Accounts
  alias Aveline.Workspaces
  alias AvelineWeb.Api.Envelope

  def show(conn, %{"code" => code}) do
    # Optional auth: resolve the session user by hand (this route lives
    # outside :papi_auth so signed-out visitors can load the invite).
    user =
      case get_session(conn, :user_id) do
        nil -> nil
        id -> Accounts.get_user(id)
      end

    case Workspaces.get_active_invite_by_code(code) do
      nil ->
        Envelope.err(conn, 404, "not_found", "This invite link is no longer valid.")

      invite ->
        ws = invite.workspace

        Envelope.ok(conn, %{
          workspace: %{id: ws.id, slug: ws.slug, name: ws.name},
          already_member: user != nil and Workspaces.member?(ws.id, user.id)
        })
    end
  end

  def accept(conn, %{"code" => code}) do
    user = conn.assigns.current_user

    case Workspaces.get_active_invite_by_code(code) do
      nil ->
        Envelope.err(conn, 404, "not_found", "This invite link is no longer valid.")

      invite ->
        {:ok, _} = Workspaces.ensure_member(invite.workspace_id, user.id)
        ws = invite.workspace
        Envelope.ok(conn, %{workspace: %{id: ws.id, slug: ws.slug, name: ws.name}})
    end
  end
end
