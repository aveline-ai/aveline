defmodule AvelineWeb.AuthController do
  use AvelineWeb, :controller

  alias Aveline.Accounts
  alias Aveline.Accounts.UserToken

  def register(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        token = Accounts.generate_user_session_token!(user)

        conn
        |> put_session(:user_token, token)
        |> put_status(:created)
        |> json(%{
          status: "ok",
          data: %{
            user: %{
              id: user.id,
              email: user.email,
              first_name: user.first_name
            }
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          errors: translate_changeset_errors(changeset)
        })
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      token = Accounts.generate_user_session_token!(user)

      conn
      |> put_session(:user_token, token)
      |> json(%{
        status: "ok",
        data: %{
          user: %{
            id: user.id,
            email: user.email,
            first_name: user.first_name
          }
        }
      })
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        status: "error",
        errors: %{
          email: ["Invalid email or password"]
        }
      })
    end
  end

  def logout(conn, _params) do
    if token = get_session(conn, :user_token) do
      Aveline.Repo.delete_all(UserToken.verify_session_token_query(token))
    end

    conn
    |> clear_session()
    |> json(%{status: "ok"})
  end

  defp translate_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
