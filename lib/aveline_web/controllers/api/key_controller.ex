defmodule AvelineWeb.Api.KeyController do
  @moduledoc """
  API key self-service — list, mint, revoke your own keys, so agents can
  rotate their credentials. The plaintext appears exactly once, in the
  create response; only its hash persists. Revoking the last active key
  is refused (`last_key`) so an account is never stranded keyless.
  """
  use AvelineWeb, :controller

  alias Aveline.Tokens
  alias AvelineWeb.Api.Envelope

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    user = conn.assigns.current_user
    keys = Tokens.list_active_for_user(user.id)
    Envelope.ok(conn, %{keys: Enum.map(keys, &key_map/1)})
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    name = (params["name"] || "") |> to_string() |> String.trim()

    with :ok <- validate_name(name),
         {:ok, token, plaintext} <- Tokens.mint(user.id, name) do
      Envelope.ok(conn, key_map(token) |> Map.put(:key, plaintext))
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, _} <- Tokens.revoke_guarded(user.id, id) do
      Envelope.ok(conn, %{revoked: id})
    end
  end

  defp validate_name(""), do: {:error, "name is required — e.g. \"laptop\" or \"ci\""}
  defp validate_name(_), do: :ok

  defp key_map(t) do
    %{
      id: t.id,
      name: t.name,
      masked: Tokens.masked(t),
      created_at: DateTime.to_iso8601(t.inserted_at),
      last_used_at: t.last_used_at && DateTime.to_iso8601(t.last_used_at)
    }
  end
end
