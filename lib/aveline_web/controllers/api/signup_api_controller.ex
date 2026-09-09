defmodule AvelineWeb.Api.SignupApiController do
  @moduledoc """
  JSON signup for the Elm SPA (fe-auth). Mirrors the submit behavior of
  SignupLive / InviteLive: same validation order and the same messages.

  Flow (matching the LiveViews' preview-token pattern):

    1. `GET /papi/signup/preview-token` — mint a plaintext API key the
       form shows up-front (nothing is persisted).
    2. `POST /papi/signup` — create the account. The preview token comes
       back in the body so the key the user copied is the key that lands
       (hashed) in the DB. With `invite_code`, joins that workspace
       instead of creating one (InviteLive's signup branch).

  `GET /papi/signup/username-status` backs InviteLive's live "Username
  taken." check; format-level messages are computed client-side.
  """
  use AvelineWeb, :controller

  alias Aveline.Accounts
  alias Aveline.Slug
  alias Aveline.Tokens
  alias Aveline.Workspaces
  alias AvelineWeb.Api.Envelope

  @username_regex ~r/^[a-z0-9][a-z0-9-]*$/

  def preview_token(conn, _params) do
    Envelope.ok(conn, %{token: Tokens.generate_plaintext()})
  end

  def username_status(conn, params) do
    username = normalize_username(params["username"])
    taken = username != "" and Accounts.get_user_by_username(username) != nil
    Envelope.ok(conn, %{username: username, taken: taken})
  end

  def create(conn, params) do
    username = normalize_username(params["username"])
    invite_code = presence(params["invite_code"])
    workspace_name = params["workspace_name"] |> to_string() |> String.trim()
    copied = params["copied"] in [true, "true"]
    token = params["token"] |> to_string()

    context = if invite_code, do: :invite, else: :signup
    username_err = check_username(username, context)

    workspace_err =
      cond do
        invite_code != nil ->
          nil

        workspace_name == "" ->
          "Pick a workspace name."

        Slug.derive(workspace_name) in [nil, ""] ->
          "Workspace name needs at least one letter or digit."

        true ->
          nil
      end

    copy_err =
      if copied,
        do: nil,
        else: "Copy the API key first. You will not be able to see it again."

    invite = invite_code && Workspaces.get_active_invite_by_code(invite_code)

    # Priority mirrors the LiveViews: username → workspace → copy.
    first_error = username_err || workspace_err || copy_err

    cond do
      invite_code != nil and invite == nil ->
        Envelope.err(conn, 404, "not_found", "This invite link is no longer valid.")

      first_error != nil ->
        Envelope.err(conn, 422, "validation_failed", first_error)

      true ->
        attrs =
          %{"username" => username, "plaintext_token" => token}
          |> then(fn a ->
            if invite_code,
              do: Map.put(a, "invite_code", invite_code),
              else: Map.put(a, "workspace_name", workspace_name)
          end)

        case Accounts.signup(attrs) do
          {:ok, %{user: user, workspace: ws, token: plaintext}} ->
            workspace = ws || invite.workspace

            Envelope.ok(conn, %{
              user: %{id: user.id, username: user.username},
              workspace: %{id: workspace.id, slug: workspace.slug, name: workspace.name},
              token: plaintext
            })

          {:error, %Ecto.Changeset{} = cs} ->
            Envelope.err(conn, 422, "validation_failed", format_changeset(cs))

          {:error, other} ->
            Envelope.err(conn, 422, "validation_failed", "Signup failed: #{inspect(other)}")
        end
    end
  end

  defp normalize_username(raw), do: raw |> to_string() |> String.trim() |> String.downcase()

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(s) when is_binary(s), do: s
  defp presence(_), do: nil

  # Same checks (and messages) as SignupLive.check_username/1 and
  # InviteLive.check_username/1 — the two flows word them differently.
  defp check_username("", _context), do: nil

  defp check_username(username, context) do
    cond do
      String.length(username) < 2 -> too_short(context)
      String.length(username) > 60 -> too_long(context)
      not Regex.match?(@username_regex, username) -> bad_format(context)
      Accounts.get_user_by_username(username) -> "Username taken."
      true -> nil
    end
  end

  defp too_short(:signup), do: "Username too short (min 2)."
  defp too_short(:invite), do: "Too short (minimum 2 characters)."

  defp too_long(:signup), do: "Username too long (max 60)."
  defp too_long(:invite), do: "Too long (max 60 characters)."

  defp bad_format(:signup), do: "Lowercase letters, digits, and hyphens only."

  defp bad_format(:invite),
    do: "Use lowercase letters, digits, and hyphens. Must start with a letter or digit."

  defp format_changeset(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end
