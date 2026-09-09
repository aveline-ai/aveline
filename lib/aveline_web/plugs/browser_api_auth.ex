defmodule AvelineWeb.Plugs.BrowserApiAuth do
  @moduledoc """
  Session-cookie auth for the Elm SPA's /papi requests. Same contract as
  ApiAuth (assigns :current_user, 401 envelope on failure) but the
  credential is the Phoenix session, not a bearer token. CSRF protection
  comes from `protect_from_forgery` in the :papi pipeline — the SPA sends
  the token in the x-csrf-token header on every request.
  """
  import Plug.Conn

  alias Aveline.Accounts
  alias AvelineWeb.Api.Envelope

  def init(opts), do: opts

  def call(conn, _opts) do
    with user_id when is_binary(user_id) <- get_session(conn, :user_id),
         %_{} = user <- Accounts.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> Envelope.err(401, "unauthorized", "Not signed in.")
        |> halt()
    end
  end
end
