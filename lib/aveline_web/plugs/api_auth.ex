defmodule AvelineWeb.Plugs.ApiAuth do
  @moduledoc """
  Parses `Authorization: Bearer avl_...`, looks up the token by sha256 hash,
  assigns `:current_user`, and touches `last_used_at`. Returns 401 with the
  canonical API envelope on any failure.
  """
  import Plug.Conn

  alias Aveline.Tokens
  alias AvelineWeb.Api.Envelope

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
      _ ->
        conn
        |> Envelope.err(401, "unauthorized", "Missing or invalid bearer token.")
        |> halt()
    end
  end

  defp parse_bearer("Bearer " <> token), do: {:ok, token}
  defp parse_bearer("bearer " <> token), do: {:ok, token}
  defp parse_bearer(_), do: :error
end
