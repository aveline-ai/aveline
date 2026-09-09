defmodule AvelineWeb.Api.SessionApiController do
  @moduledoc """
  JSON login/logout for the Elm SPA. Mirrors SessionController's
  token-paste flow (the token IS the credential) but returns an envelope
  instead of redirecting, so Elm owns navigation.
  """
  use AvelineWeb, :controller

  alias Aveline.Tokens
  alias AvelineWeb.Api.Envelope

  def create(conn, %{"token" => plaintext}) do
    case Tokens.verify(plaintext) do
      nil ->
        Envelope.err(conn, 401, "invalid_token", "Invalid token.")

      token ->
        Tokens.touch_last_used(token)

        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, token.user_id)
        |> Envelope.ok(%{user: %{id: token.user.id, username: token.user.username}})
    end
  end

  def create(conn, _params),
    do: Envelope.err(conn, 422, "validation_failed", "Missing required field: token.")

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> Envelope.ok(%{})
  end
end
