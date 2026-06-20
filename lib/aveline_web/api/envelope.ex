defmodule AvelineWeb.Api.Envelope do
  @moduledoc """
  Canonical JSON shape for every API response. Optimized for an
  AI agent caller (the CLI is agent-first, see CLI README).

  Success:
      %{"ok" => true, ...payload}

  Failure:
      %{"ok" => false, "error" => %{"code" => "...", "message" => "...", "details" => optional}}

  Payload keys live at the top level so the caller can read them
  without a wrapper hop. Failures nest under `error` so the agent
  can pattern-match on `error.code` to branch its retry logic.

  Use `ok/2` and `err/2,3,4` from controllers; the fallback
  controller renders `err/...` for plumbing-level errors. See
  `AvelineWeb.Api.ErrorCodes` for the catalog of codes.
  """

  import Plug.Conn

  @doc """
  Send a success envelope. `payload` is merged into the response object
  alongside `"ok" => true`. Pass an empty map for a no-payload success.

      ok(conn, %{slug: "deploy-guide"})
      # => {"ok": true, "slug": "deploy-guide"}
  """
  def ok(conn, payload \\ %{}) when is_map(payload) do
    body = Map.put(stringify(payload), "ok", true)

    conn
    |> put_status(:ok)
    |> Phoenix.Controller.json(body)
  end

  @doc """
  Send a failure envelope. `status` is the HTTP status, `code` is the
  machine-readable code (see ErrorCodes), `message` is the human-
  readable line for the agent's working memory. Optional `details` is
  a map of structured info the agent may need to recover (rare).

      err(conn, 404, "not_found", "Doc not found.")
      err(conn, 422, "disposition_missing",
          "Open comments anchored to touched blocks must be dispositioned.",
          %{missing: ["c_abc"]})
  """
  def err(conn, status, code, message, details \\ nil)
      when is_integer(status) and is_binary(code) and is_binary(message) do
    error =
      %{"code" => code, "message" => message}
      |> maybe_put_details(details)

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{"ok" => false, "error" => error})
  end

  defp maybe_put_details(map, nil), do: map
  defp maybe_put_details(map, details) when map_size(details) == 0, do: map
  defp maybe_put_details(map, details), do: Map.put(map, "details", stringify(details))

  # Atom keys → string keys at the top level. Nested values pass through
  # — JSON encoding will handle them. Lists are passed through too.
  defp stringify(map) when is_map(map) do
    Enum.into(map, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
