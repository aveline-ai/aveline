defmodule AvelineWeb.ErrorHandler do
  @moduledoc """
  A module for handling errors.
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2, halt: 1]

  # Refer to: https://hexdocs.pm/plug/1.15.3/Plug.Conn.Status.html to see the `http_status` options
  @error_codes_and_default_messages %{
    unauthenticated: %{
      http_status: :unauthorized,
      code: 1,
      default_message: "You must be logged in to access this resource."
    },
    already_authenticated: %{
      http_status: :conflict,
      code: 2,
      default_message: "You are already logged in."
    }
  }

  def put_unauthenticated_error(conn) do
    conn
    |> put_error_and_status(@error_codes_and_default_messages.unauthenticated)
  end

  def put_already_authenticated_error(conn) do
    conn
    |> put_error_and_status(@error_codes_and_default_messages.already_authenticated)
  end

  # Private

  def put_error_and_status(
        conn,
        %{http_status: http_status, code: code, default_message: default_message},
        override_message \\ nil
      ) do
    message = override_message || default_message

    conn
    |> put_status(http_status)
    |> json(%{error: %{code: code, message: message}})
    |> halt()
  end
end
