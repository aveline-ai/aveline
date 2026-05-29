defmodule AvelineWeb.LiveSession do
  @moduledoc """
  Lightweight session helper for v0 LiveViews.

  Resolves the current user from the session cookie's `user_id`, which is
  set by `/login/:token` or `POST /login` after `Aveline.Tokens.verify/1`
  succeeds.

  Drops to `nil` when no session is set — the page should redirect to
  /signup or /login.
  """

  alias Aveline.Accounts
  alias Aveline.Workspaces

  def current_user(session) when is_map(session) do
    case session["user_id"] do
      nil -> nil
      id -> Accounts.get_user(id)
    end
  end

  def current_user(_), do: nil

  @doc """
  Resolve workspace + verify membership. Returns `{:ok, ws}`, `:not_found`, or
  `:forbidden`.
  """
  def fetch_workspace_for_user(slug, %{id: user_id}) when is_binary(slug) do
    case Workspaces.get_active_by_slug(slug) do
      nil ->
        :not_found

      ws ->
        if Workspaces.member?(ws.id, user_id), do: {:ok, ws}, else: :forbidden
    end
  end

  def fetch_workspace_for_user(_slug, nil), do: :forbidden
end
