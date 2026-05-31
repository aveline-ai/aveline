defmodule AvelineWeb.SessionController do
  @moduledoc """
  v0 web auth: paste an API token in `/login/avl_...`, get a session cookie,
  redirect home. No passwords, no signup — the token IS the credential.

  Optional `?next=/path` parameter on POST /login lets the signup flow
  drop the new user into a specific workspace after they save the token.
  Only relative paths starting with `/` are accepted (so an attacker
  can't redirect off-site).
  """
  use AvelineWeb, :controller

  alias Aveline.Tokens

  def create(conn, %{"token" => plaintext} = params) do
    next = safe_next(params["next"])

    case Tokens.verify(plaintext) do
      nil ->
        conn
        |> put_flash(:error, "Invalid token.")
        |> redirect(to: next)

      token ->
        Tokens.touch_last_used(token)

        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, token.user_id)
        |> redirect(to: next)
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end

  defp safe_next(nil), do: ~p"/"
  defp safe_next(""), do: ~p"/"

  defp safe_next(s) when is_binary(s) do
    if String.starts_with?(s, "/") and not String.starts_with?(s, "//"), do: s, else: ~p"/"
  end

  defp safe_next(_), do: ~p"/"
end
