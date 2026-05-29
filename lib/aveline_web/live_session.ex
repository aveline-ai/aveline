defmodule AvelineWeb.LiveSession do
  @moduledoc """
  Lightweight session helper for v0 LiveViews. Real session auth is v0.1; for
  now the "current user" is the user whose email is in `SEED_USER_EMAIL`.
  """

  alias Aveline.Accounts
  alias Aveline.Workspaces

  def current_user do
    case System.get_env("SEED_USER_EMAIL") do
      nil -> nil
      "" -> nil
      email -> Accounts.get_user_by_email(email)
    end
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
