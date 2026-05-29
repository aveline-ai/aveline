defmodule AvelineWeb.LiveSession do
  @moduledoc """
  Lightweight session helper for v0 LiveViews.

  Resolution order for the current user:
    1. `user_id` in the session cookie (set by `/login/:token`)
    2. `SEED_USER_EMAIL` env var (escape hatch for scripted runs)
    3. `alice@local.test` in dev so the browser flow works fresh

  Real session auth with refresh, expiry, etc. is v0.1.
  """

  alias Aveline.Accounts
  alias Aveline.Workspaces

  @dev_default_email "alice@local.test"

  def current_user(session) when is_map(session) do
    case session["user_id"] do
      nil -> fallback_user()
      id -> Accounts.get_user(id) || fallback_user()
    end
  end

  def current_user(_), do: fallback_user()

  defp fallback_user do
    email =
      case System.get_env("SEED_USER_EMAIL") do
        nil -> @dev_default_email
        "" -> @dev_default_email
        e -> e
      end

    Accounts.get_user_by_email(email)
  end

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
