defmodule AvelineWeb.Api.KeyController do
  @moduledoc """
  API key self-service — list, mint, revoke your own keys, so agents can
  rotate their credentials. The plaintext appears exactly once, in the
  create response; only its hash persists. Revoking the last active key
  is refused (`last_key`) so an account is never stranded keyless.

  All decisions live in src/aveline/handlers/api_keys.gleam; this module
  only coerces params and renders the typed results.
  """
  use AvelineWeb, :controller

  import Aveline.Gleam.Interop, only: [unopt: 1]

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    keys = :aveline@handlers@api_keys.index(CtxBuilder.build(), actor(conn))
    Envelope.ok(conn, %{keys: Enum.map(keys, &key_map/1)})
  end

  def create(conn, params) do
    name = to_string(params["name"] || "")

    case :aveline@handlers@api_keys.create(CtxBuilder.build(), actor(conn), name) do
      {:ok, {:minted_key, key, plaintext}} ->
        Envelope.ok(conn, key |> key_map() |> Map.put(:key, plaintext))

      {:error, err} ->
        GleamAdapter.error(err)
    end
  end

  def delete(conn, %{"id" => id}) do
    case :aveline@handlers@api_keys.delete(CtxBuilder.build(), actor(conn), id) do
      {:ok, revoked} -> Envelope.ok(conn, %{revoked: revoked})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  # /api/keys is not workspace-scoped, so the handler takes the bare Actor.
  defp actor(conn) do
    user = conn.assigns.current_user
    {:actor, user.id, user.username}
  end

  defp key_map({:api_key, id, name, masked, created_at, last_used_at}) do
    %{
      id: id,
      name: name,
      masked: masked,
      created_at: created_at,
      last_used_at: unopt(last_used_at)
    }
  end
end
