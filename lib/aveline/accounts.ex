defmodule Aveline.Accounts do
  @moduledoc """
  The Accounts context.

  Users are not soft-deleted in v0; they're a foundational table referenced
  everywhere. `base_query/0` is provided for shape consistency with other
  contexts.
  """

  import Ecto.Query
  alias Aveline.Accounts.User
  alias Aveline.Repo
  alias Aveline.Tokens
  alias Aveline.Workspaces
  alias Ecto.Multi

  def base_query, do: from(u in User)

  def get_user(id) when is_binary(id), do: Repo.get(User, id)
  def get_user(_), do: nil

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def get_user_by_email(_), do: nil

  def create_user(attrs) do
    %User{}
    |> User.changeset(normalize_email(attrs))
    |> Repo.insert()
  end

  def upsert_user_by_email(attrs) do
    attrs = normalize_email(attrs)

    case get_user_by_email(attrs["email"] || attrs[:email]) do
      nil -> create_user(attrs)
      user -> {:ok, user}
    end
  end

  defp normalize_email(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, "email") and is_binary(attrs["email"]) and attrs["email"] != "" ->
        Map.put(attrs, "email", String.downcase(attrs["email"]))

      Map.has_key?(attrs, :email) and is_binary(attrs[:email]) and attrs[:email] != "" ->
        Map.put(attrs, :email, String.downcase(attrs[:email]))

      true ->
        attrs
    end
  end

  @doc """
  Single-shot signup. Creates the user, a personal workspace, the
  workspace membership, and mints an initial API token — all in one
  transaction. Returns `{:ok, %{user, workspace, token: plaintext}}` or
  `{:error, %Ecto.Changeset{}}` if the username is taken / invalid.

  The plaintext token is returned ONCE and never reconstructible
  afterwards. The caller is responsible for showing it to the user.
  """
  def signup(attrs) when is_map(attrs) do
    normalized = normalize_signup_attrs(attrs)

    Multi.new()
    |> Multi.insert(:user, User.changeset(%User{}, normalized))
    |> Multi.run(:workspace, fn _repo, %{user: user} ->
      slug = workspace_slug_for(user.username)

      Workspaces.create_workspace(%{
        "slug" => slug,
        "name" => "Personal",
        "created_by_id" => user.id
      })
    end)
    |> Multi.run(:membership, fn _repo, %{user: user, workspace: ws} ->
      Workspaces.ensure_member(ws.id, user.id)
    end)
    |> Multi.run(:token, fn _repo, %{user: user} ->
      case Tokens.mint(user.id, "initial signup token") do
        {:ok, _t, plaintext} -> {:ok, plaintext}
        other -> other
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, workspace: ws, token: plaintext}} ->
        {:ok, %{user: user, workspace: ws, token: plaintext}}

      {:error, _step, %Ecto.Changeset{} = cs, _changes} ->
        {:error, cs}

      {:error, _step, other, _changes} ->
        {:error, other}
    end
  end

  defp normalize_signup_attrs(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.update("username", "", fn
      nil -> ""
      v when is_binary(v) -> v |> String.trim() |> String.downcase()
      v -> v
    end)
    |> Map.update("display_name", nil, fn
      nil -> nil
      "" -> nil
      v when is_binary(v) -> String.trim(v)
      v -> v
    end)
    |> normalize_email()
  end

  @doc """
  Returns the workspace slug we mint for a fresh user. Right now: their
  username. If it clashes (extremely unlikely since usernames are unique),
  Postgres will surface a constraint error in the Multi.
  """
  def workspace_slug_for(username) when is_binary(username), do: username
end
