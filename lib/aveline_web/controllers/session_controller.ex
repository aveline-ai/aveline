defmodule AvelineWeb.SessionController do
  @moduledoc """
  v0 web auth: paste an API token in `/login/avl_...`, get a session cookie,
  redirect home. No passwords, no signup — the token IS the credential.
  """
  use AvelineWeb, :controller

  alias Aveline.Tokens

  def create(conn, %{"token" => plaintext}) do
    case Tokens.verify(plaintext) do
      nil ->
        conn
        |> put_flash(:error, "Invalid token.")
        |> redirect(to: ~p"/")

      token ->
        Tokens.touch_last_used(token)

        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, token.user_id)
        |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end
end
