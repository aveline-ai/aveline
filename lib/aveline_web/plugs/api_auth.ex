defmodule AvelineWeb.Plugs.ApiAuth do
  @moduledoc """
  Parses `Authorization: Bearer avl_...`, looks up the token by sha256 hash,
  assigns `:current_user`, and touches `last_used_at`. Returns 401 with the
  API error envelope on any failure.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_view: 2, render: 3]

  alias Aveline.Tokens
  alias AvelineWeb.Api.ErrorJSON

  def init(opts), do: opts

  def call(conn, _opts) do
    with [auth_header] <- get_req_header(conn, "authorization"),
         {:ok, plaintext} <- parse_bearer(auth_header),
         %_{user: %_{} = user} = token <- Tokens.verify(plaintext) do
      Tokens.touch_last_used(token)

      conn
      |> assign(:current_user, user)
      |> assign(:current_token, token)
    else
      _ -> unauthorized(conn)
    end
  end

  defp parse_bearer("Bearer " <> token), do: {:ok, token}
  defp parse_bearer("bearer " <> token), do: {:ok, token}
  defp parse_bearer(_), do: :error

  defp unauthorized(conn) do
    conn
    |> put_status(401)
    |> put_view(json: ErrorJSON)
    |> render(:error, %{
      code: "unauthorized",
      message: "Missing or invalid bearer token."
    })
    |> halt()
  end
end
