defmodule AvelineWeb.AuthPlug do
  @moduledoc """
  A handful of useful plugs for authentication.
  """

  import Plug.Conn

  alias Aveline.Accounts
  alias AvelineWeb.ErrorHandler

  alias Aveline.LittleLogger, as: LL
  alias Sentry

  def put_current_user_from_session(conn, _opts) do
    user_token = get_session(conn, :user_token)

    cond do
      # This is for easier testing, if there is a user already in the connection, we honor it. This way tests can
      # just include a user in the assigns and we don't need any elobrate mocking.
      user = conn.assigns[:current_user] ->
        put_current_user(conn, user)

      user = user_token && Accounts.get_user_by_session_token(user_token) ->
        put_current_user(conn, user)

      true ->
        put_current_user(conn, nil)
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> ErrorHandler.put_unauthenticated_error()
    end
  end

  def require_no_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> ErrorHandler.put_already_authenticated_error()
    else
      conn
    end
  end

  # Private

  defp put_current_user(conn, user) do
    if user do
      LL.metadata_add_current_user_id(user.id)
      Sentry.Context.set_user_context(%{id: user.id, email: user.email})
    end

    conn
    |> assign(:current_user, user)
  end
end
