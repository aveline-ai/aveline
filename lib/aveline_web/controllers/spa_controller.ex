defmodule AvelineWeb.SpaController do
  @moduledoc """
  Serves the Elm SPA shell. One HTML page for every browser route; Elm
  reads the injected bootstrap (csrf + current user) and owns everything
  after that.
  """
  use AvelineWeb, :controller

  alias Aveline.Accounts

  def index(conn, _params) do
    user =
      case get_session(conn, :user_id) do
        nil -> nil
        id -> Accounts.get_user(id)
      end

    bootstrap = %{
      csrf: Plug.CSRFProtection.get_csrf_token(),
      user: user && %{id: user.id, username: user.username}
    }

    conn
    |> put_root_layout(false)
    |> put_layout(false)
    |> render(:index, bootstrap: bootstrap, page_title: "Aveline")
  end
end
