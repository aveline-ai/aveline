defmodule AvelineWeb.Api.DocShowController do
  @moduledoc """
  Thin read endpoints backing the Elm doc-show page (fe-doc-show port).

  Each action is a straight composition of the same context calls
  `AvelineWeb.DocShowLive.mount/3` makes — no business logic lives here.
  Routed only under /papi (see the `fe-doc-show routes` block in the
  router); the agent-facing /api surface is unchanged.
  """
  use AvelineWeb, :controller

  alias Aveline.Comments
  alias Aveline.Docs
  alias Aveline.DocViews
  alias Aveline.Kudos
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  @doc "Kudos + view state for the viewer, without toggling anything."
  def kudos_state(conn, %{"doc_slug" => slug}) do
    with {:ok, item} <- fetch_readable(conn, slug) do
      user = conn.assigns.current_user

      Envelope.ok(conn, %{
        given_by_me: Kudos.given_by?(item.base_doc_id, user.id),
        count: Kudos.count_for_base(item.base_doc_id),
        view_count: DocViews.count_for_base(item.base_doc_id)
      })
    end
  end

  @doc """
  The doc as the browser page reads it — same `doc_full` shape as
  GET /docs/:doc_slug, but records a *human* "read" event instead of the
  agent one that endpoint logs (`DocViews` dedupes per actor type, so
  the SPA must not hit the agent-flavored show). Blocks come enriched,
  charts as pending config — the page runs them itself.
  """
  def reader(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, item} <- fetch_readable(conn, slug) do
      DocViews.record(ws.id, item.base_doc_id, user.id, "human")
      item = %{item | blocks: Docs.enrich_blocks(item.blocks || [], ws.id, run_charts: false, viewer: user.id)}
      Envelope.ok(conn, %{doc: Views.doc_full(item)})
    end
  end

  @doc """
  Version history for the switcher: the standard version shape plus
  `comment_dispositions` (for the "Resolved 2 · Re-anchored 1" summary
  line) and `updated_at`.
  """
  def history(conn, %{"doc_slug" => slug}) do
    with {:ok, item} <- fetch_readable(conn, slug) do
      versions =
        item.base_doc_id
        |> Docs.list_versions()
        |> Enum.map(fn v ->
          v
          |> Views.doc_version()
          |> Map.merge(%{
            "updated_at" => iso(v.updated_at),
            "comment_dispositions" => v.comment_dispositions || []
          })
        end)

      Envelope.ok(conn, %{versions: versions, current_version: item.version_number})
    end
  end

  @doc """
  Comments pinned to one doc-version (auto-forward gives every version
  its own snapshot). `?include_deleted=true` adds soft-deleted rows (the
  "all" comment view). On top of the standard comment shape each row
  carries `resolved_by_doc_id` (resolved-thread collapse keys on it) and
  `context_snippet` — the first words of the block the comment was
  originally anchored to, used as the caption on orphaned threads.
  """
  def version_comments(conn, %{"doc_slug" => slug, "version_number" => n_raw} = params) do
    with {:ok, current} <- fetch_readable(conn, slug),
         {n, ""} <- Integer.parse(to_string(n_raw)),
         %_{} = doc <- Docs.get_version(current.base_doc_id, n) || {:error, :not_found} do
      comments =
        doc.id
        |> Comments.list_for_doc_version(include_deleted: params["include_deleted"] == "true")
        |> Enum.map(&reader_comment/1)

      Envelope.ok(conn, %{doc_version_id: doc.id, comments: comments})
    else
      :error -> {:error, :not_found}
      err -> err
    end
  end

  @doc """
  Bust a chart's cached inputs, then run it — the reader's ↻ refresh /
  historical Run control. Deliberately mirrors the LV `chart_rerun`
  event (which also always busts). `?version=N` locates the block in a
  historical version whose blocks are no longer in the current one.
  """
  def rerun_block(conn, %{"doc_slug" => slug, "block_id" => block_id} = params) do
    ws = conn.assigns.current_workspace

    with {:ok, current} <- fetch_readable(conn, slug),
         {:ok, doc} <- resolve_version(current, params["version"]),
         %{"type" => "chart"} = block <- find_chart(doc.blocks, block_id) || {:error, :not_found} do
      Docs.bust_chart(ws.id, block)

      case Docs.run_chart(ws.id, block) do
        %{"error" => msg} -> {:error, :query_failed, msg}
        result -> Envelope.ok(conn, result)
      end
    end
  end

  # ===== Helpers =====

  defp resolve_version(current, nil), do: {:ok, current}
  defp resolve_version(current, ""), do: {:ok, current}

  defp resolve_version(current, raw) do
    case Integer.parse(to_string(raw)) do
      {n, ""} ->
        case Docs.get_version(current.base_doc_id, n) do
          nil -> {:error, :not_found}
          doc -> {:ok, doc}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp find_chart(blocks, block_id) do
    Enum.find(blocks || [], &(&1["type"] == "chart" and &1["id"] == block_id))
  end

  defp reader_comment(c) do
    c
    |> Views.comment()
    |> Map.merge(%{
      "resolved_by_doc_id" => c.resolved_by_doc_id,
      "context_snippet" => context_snippet(c)
    })
  end

  # First line / first few words of the block the comment originally
  # anchored to — from the comment's own (preloaded) doc-version blocks.
  # Same snippets the LV shows on orphan cards.
  defp context_snippet(%{block_id: bid, doc: %{blocks: blocks}}) when is_binary(bid) and is_list(blocks) do
    case Enum.find(blocks, fn b -> is_map(b) and b["id"] == bid end) do
      nil -> nil
      block -> block_snippet(block)
    end
  end

  defp context_snippet(_), do: nil

  defp block_snippet(%{"type" => "heading", "text" => text}), do: String.slice(text || "", 0, 80)
  defp block_snippet(%{"type" => "code", "content" => content}), do: String.slice(content || "", 0, 80)

  defp block_snippet(%{"type" => "paragraph", "content" => content}) when is_list(content) do
    content
    |> Enum.map_join("", fn s -> s["text"] || "" end)
    |> String.slice(0, 120)
  end

  defp block_snippet(%{"type" => "list", "items" => [first | _]}) when is_map(first) do
    case first["content"] do
      [_ | _] = c -> c |> Enum.map_join("", fn s -> s["text"] || "" end) |> String.slice(0, 120)
      _ -> nil
    end
  end

  defp block_snippet(_), do: nil

  # One access rule for every by-slug endpoint — same doctrine as
  # DocController: inaccessible and nonexistent are indistinguishable.
  defp fetch_readable(conn, slug) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    case Docs.get_current_by_slug(ws.id, slug) do
      nil -> {:error, :not_found}
      item -> if Docs.member_can_read?(item, user.id), do: {:ok, item}, else: {:error, :not_found}
    end
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
end
