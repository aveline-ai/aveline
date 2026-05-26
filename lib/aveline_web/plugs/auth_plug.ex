defmodule AvelineWeb.AuthPlug do
  @moduledoc """
  Auth plugs. Stubs for v0 — real session/token auth will be wired up later.
  """

  import Plug.Conn

  alias AvelineWeb.ErrorHandler

  @doc """
  Loads the current user into the conn from the session, if any. v0: always nil.
  """
  def put_current_user_from_session(conn, _opts) do
    assign(conn, :current_user, conn.assigns[:current_user])
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      ErrorHandler.put_unauthenticated_error(conn)
    end
  end

  def require_no_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      ErrorHandler.put_already_authenticated_error(conn)
    else
      conn
    end
  end
end
