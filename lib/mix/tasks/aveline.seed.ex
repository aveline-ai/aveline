defmodule Mix.Tasks.Aveline.Seed do
  @moduledoc """
  Idempotent seed task.

  Required env vars:
    * SEED_USER_EMAIL
    * SEED_USER_USERNAME
    * SEED_USER_DISPLAY_NAME (optional)
    * SEED_WORKSPACE_SLUG
    * SEED_WORKSPACE_NAME

  Prints the plaintext API token ONCE.
  """
  use Mix.Task

  alias Aveline.Accounts
  alias Aveline.Tokens
  alias Aveline.Workspaces

  @shortdoc "Seed a user, workspace, membership, and API token."

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    email = require_env("SEED_USER_EMAIL")
    username = require_env("SEED_USER_USERNAME")
    display_name = System.get_env("SEED_USER_DISPLAY_NAME")
    workspace_slug = require_env("SEED_WORKSPACE_SLUG")
    workspace_name = require_env("SEED_WORKSPACE_NAME")

    user =
      case Accounts.get_user_by_email(email) do
        nil ->
          {:ok, u} =
            Accounts.create_user(%{
              "email" => email,
              "username" => username,
              "display_name" => display_name
            })

          IO.puts("[seed] created user #{u.username} (#{u.email})")
          u

        u ->
          IO.puts("[seed] user already exists: #{u.username} (#{u.email})")
          u
      end

    workspace =
      case Workspaces.get_active_by_slug(workspace_slug) do
        nil ->
          {:ok, w} =
            Workspaces.create_workspace(%{
              "slug" => workspace_slug,
              "name" => workspace_name,
              "created_by_id" => user.id
            })

          IO.puts("[seed] created workspace #{w.slug}")
          w

        w ->
          IO.puts("[seed] workspace already exists: #{w.slug}")
          w
      end

    case Workspaces.ensure_member(workspace.id, user.id) do
      {:ok, _} -> IO.puts("[seed] ensured membership")
      other -> Mix.raise("[seed] failed to ensure membership: #{inspect(other)}")
    end

    {:ok, _token, plaintext} = Tokens.mint(user.id, "#{username} seed token")

    IO.puts("")
    IO.puts("[seed] ===========================================================")
    IO.puts("[seed] API TOKEN (shown ONCE — copy now):")
    IO.puts("[seed]   #{plaintext}")
    IO.puts("[seed] ===========================================================")
    IO.puts("")
  end

  defp require_env(name) do
    case System.get_env(name) do
      nil -> Mix.raise("Missing required env var: #{name}")
      "" -> Mix.raise("Missing required env var: #{name}")
      val -> val
    end
  end
end
