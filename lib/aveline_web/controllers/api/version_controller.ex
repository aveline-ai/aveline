defmodule AvelineWeb.Api.VersionController do
  @moduledoc """
  Version history of a doc.

  GET /docs/:slug/versions               — list metadata for every version
  GET /docs/:slug/versions/:version_num  — full body of a specific version
  """
  use AvelineWeb, :controller

  alias Aveline.Docs
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace

    case Docs.get_current_by_slug(ws.id, slug) do
      nil ->
        {:error, :not_found}

      doc ->
        versions = Docs.list_versions(doc.base_doc_id)

        Envelope.ok(conn, %{
          versions: Enum.map(versions, &Views.doc_version/1),
          current_version: doc.version_number
        })
    end
  end

  def show(conn, %{"doc_slug" => slug, "version_number" => n_raw}) do
    ws = conn.assigns.current_workspace

    with %_{} = current <- Docs.get_current_by_slug(ws.id, slug) || {:error, :not_found},
         {n, ""} <- Integer.parse(to_string(n_raw)),
         %_{} = doc <- Docs.get_version(current.base_doc_id, n) || {:error, :not_found} do
      # Config only, no chart execution — historical SQL is never fired
      # at a customer database on read (agents run it via run-block).
      doc = %{doc | blocks: Docs.enrich_blocks(doc.blocks || [], ws.id, run_charts: false)}
      Envelope.ok(conn, %{doc: Views.doc_full(doc)})
    else
      :error -> {:error, :not_found}
      err -> err
    end
  end
end
