defmodule AvelineWeb.Api.VersionController do
  @moduledoc """
  Version history of a doc — thin adapter over the Gleam handler
  (src/aveline/handlers/doc_versions.gleam).

  GET /docs/:slug/versions               — list metadata for every version
  GET /docs/:slug/versions/:version_num  — full body of a specific version
  """
  use AvelineWeb, :controller

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, %{"doc_slug" => slug}) do
    case :aveline@handlers@doc_versions.index(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, {:version_list, versions, current_version}} ->
        Envelope.ok(conn, %{versions: versions, current_version: current_version})

      {:error, err} ->
        GleamAdapter.error(err)
    end
  end

  def show(conn, %{"doc_slug" => slug, "version_number" => raw}) do
    case :aveline@handlers@doc_versions.show(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           slug,
           to_string(raw)
         ) do
      {:ok, doc} -> Envelope.ok(conn, %{doc: doc})
      {:error, err} -> GleamAdapter.error(err)
    end
  end
end
