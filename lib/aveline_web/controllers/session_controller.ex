defmodule AvelineWeb.SessionController do
  use AvelineWeb, :controller

  alias Aveline.Account
  alias Aveline.Config
  alias AvelineWeb.Auth

  def login_with_code(conn, %{"code" => code}) do
    case Account.get_user_for_valid_login_code(code) do
      nil ->
        conn
        |> put_flash(:error, "Invalid login code.")
        |> redirect(to: Config.landing_page_url!())

      user ->
        conn
        |> Auth.login(user)
        |> redirect(to: ~p"/")
    end
  end

  def logout(conn, _) do
    Auth.logout(conn, external: Config.landing_page_url!())
  end
end
