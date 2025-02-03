defmodule AvelineWeb.SessionController do
  use AvelineWeb, :controller

  alias Aveline.Account
  alias AvelineWeb.Auth

  def login_with_code(conn, %{"code" => code}) do
    case Account.get_user_for_valid_login_code(code) do
      nil ->
        conn
        |> put_flash(:error, "Invalid login code.")
        |> redirect(to: ~p"/")

      user ->
        conn
        |> Auth.login(user)
        |> redirect(to: ~p"/")
    end
  end
end
