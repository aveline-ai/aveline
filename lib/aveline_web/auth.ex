defmodule AvelineWeb.Auth do
  @moduledoc """
  Authentication plugs and helpers.
  """
  use AvelineWeb, :verified_routes

  alias Aveline.Account
  alias Aveline.Config
  import Plug.Conn

  # Plugs

  @doc """
  A plug to set the `assigns.current_user` to be `user` or  `nil` based on the user_id in the session.
  """
  def plug_put_current_user_from_session(conn, _opts) do
    user_id = get_session(conn, :user_id)

    cond do
      user = conn.assigns[:current_user] ->
        put_current_user(conn, user)

      user = user_id && Account.get_user_by_id(user_id) ->
        put_current_user(conn, user)

      true ->
        put_current_user(conn, nil)
    end
  end

  @doc """
  A plug to halt the connection and redirect if the user is logged out [based on `assigns.current_user`].
  """
  def plug_redirect_if_logged_out(conn, _opts) do
    if conn.assigns.current_user do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "You must be logged in to access that page")
      |> Phoenix.Controller.redirect(external: Config.landing_page_url!())
      |> halt()
    end
  end

  @doc """
  A plug to halt the connection and redirect if the user is logged in [based on `assigns.current_user`].
  """
  def plug_redirect_if_logged_in(conn, _opts) do
    if conn.assigns.current_user do
      conn
      |> Phoenix.Controller.redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  @doc """
  A plug to halt the connection and redirect if the user is not an admin [based on `assigns.current_user`].
  """
  def plug_redirect_if_not_admin(conn, _opts) do
    if conn.assigns.current_user && conn.assigns.current_user.admin do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "You must be an admin to access that page")
      |> Phoenix.Controller.redirect(to: ~p"/")
      |> halt()
    end
  end

  # Auth Helpers

  @doc """
  Log a user in by storing the `user_id` in the session and setting the `assigns.current_user`.
  """
  def login(conn, user) do
    conn
    |> put_current_user(user)
    |> put_session(:user_id, user.id)
    |> configure_session(renew: true)
  end

  @doc """
  Logs a user out
  """
  def logout(conn, redirect_opts) do
    conn
    |> configure_session(drop: true)
    |> Phoenix.Controller.redirect(redirect_opts)
    |> halt()
  end

  # Private

  defp put_current_user(conn, user) do
    conn
    |> assign(:current_user, user)
  end
end
