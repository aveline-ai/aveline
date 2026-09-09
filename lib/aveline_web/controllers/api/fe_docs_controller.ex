defmodule AvelineWeb.Api.FeDocsController do
  @moduledoc """
  Read-only endpoints for the Elm Docs page (fe-docs-list port of
  WorkspaceShowLive). Two things the LiveView assembled server-side
  that the public GET /docs shape doesn't carry:

    * `index` — the doc list enriched with the card fields the page
      renders (visibility, actor, per-doc view/kudos counts) plus a
      `has_more` flag (server fetches limit+1, same trick as the LV).
    * `facets` — corpus-wide tag/author counts for the filter
      dropdowns, computed in SQL so pagination can't skew them
      (`Docs.facet_counts/2`). Author counts are keyed by username to
      save the client an id→username join.

  Same filter grammar as GET /docs: q, tag (comma list), author
  (comma list of usernames; unknown ones are ignored, mirroring the
  LV), edited (relative window like "7d"), sort, limit, offset.
  """
  use AvelineWeb, :controller

  alias Aveline.Docs
  alias Aveline.DocViews
  alias Aveline.Kudos
  alias Aveline.Workspaces
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  @default_limit 25
  @max_limit 100

  def index(conn, params) do
    ws = conn.assigns.current_workspace

    with {:ok, sort} <- parse_sort(params["sort"]),
         {:ok, limit} <- parse_limit(params["limit"]),
         {:ok, offset} <- parse_offset(params["offset"]) do
      raw =
        Docs.list_current(
          ws.id,
          filter_opts(conn, params) ++ [sort: sort, limit: limit + 1, offset: offset]
        )

      {items, has_more?} =
        case raw do
          list when length(list) > limit -> {Enum.take(list, limit), true}
          list -> {list, false}
        end

      base_ids = Enum.map(items, & &1.base_doc_id)
      view_counts = DocViews.counts_by_base(base_ids)
      kudos_counts = Kudos.counts_by_base(base_ids)

      Envelope.ok(conn, %{
        docs: Enum.map(items, &card_map(&1, view_counts, kudos_counts)),
        has_more: has_more?
      })
    end
  end

  def facets(conn, params) do
    ws = conn.assigns.current_workspace

    facets = Docs.facet_counts(ws.id, filter_opts(conn, params))

    authors =
      ws.id
      |> Workspaces.list_members()
      |> Map.new(fn m -> {m.user.username, Map.get(facets.owners, m.user.id, 0)} end)

    Envelope.ok(conn, %{tags: facets.tags, authors: authors})
  end

  # ===== Helpers =====

  # doc_summary plus the card-only fields the LV templates reach for.
  defp card_map(item, view_counts, kudos_counts) do
    item
    |> Views.doc_summary()
    |> Map.merge(%{
      "visibility" => item.visibility,
      "actor_user" => Views.user(actor_user(item)),
      "view_count" => Map.get(view_counts, item.base_doc_id, 0),
      "kudos_count" => Map.get(kudos_counts, item.base_doc_id, 0)
    })
  end

  defp actor_user(item) do
    case Map.get(item, :actor_user) do
      %Ecto.Association.NotLoaded{} -> nil
      other -> other
    end
  end

  # The filter half shared by index/facets — mirrors handle_docs_params.
  defp filter_opts(conn, params) do
    ws = conn.assigns.current_workspace

    [
      viewer: conn.assigns.current_user.id,
      tags: parse_list(params["tag"] || params["tags"]),
      owner_ids: author_ids(ws.id, parse_list(params["author"] || params["authors"])),
      search: params["q"],
      updated: params["edited"] || params["updated"]
    ]
  end

  # Unknown usernames are dropped silently — same as the LV, where an
  # unknown author chip simply can't be selected.
  defp author_ids(_ws_id, []), do: []

  defp author_ids(ws_id, usernames) do
    by_name =
      ws_id
      |> Workspaces.list_members()
      |> Map.new(fn m -> {m.user.username, m.user.id} end)

    Enum.flat_map(usernames, fn u ->
      case by_name[u] do
        nil -> []
        id -> [id]
      end
    end)
  end

  defp parse_list(nil), do: []
  defp parse_list(""), do: []
  defp parse_list(list) when is_list(list), do: Enum.uniq(list)
  defp parse_list(s) when is_binary(s), do: s |> String.split(",", trim: true) |> Enum.uniq()

  # :recent default — the page always shows an explicit sort knob.
  defp parse_sort(nil), do: {:ok, :recent}
  defp parse_sort(""), do: {:ok, :recent}
  defp parse_sort("recent"), do: {:ok, :recent}
  defp parse_sort("kudos"), do: {:ok, :kudos}
  defp parse_sort("views"), do: {:ok, :views}

  defp parse_sort(other),
    do: {:error, {:list_param_invalid, "sort must be recent | kudos | views, got: #{inspect(other)}"}}

  defp parse_limit(nil), do: {:ok, @default_limit}
  defp parse_limit(""), do: {:ok, @default_limit}

  defp parse_limit(raw) do
    case Integer.parse(to_string(raw)) do
      {n, ""} when n in 1..@max_limit ->
        {:ok, n}

      _ ->
        {:error, {:list_param_invalid, "limit must be an integer between 1 and #{@max_limit}"}}
    end
  end

  defp parse_offset(nil), do: {:ok, 0}
  defp parse_offset(""), do: {:ok, 0}

  defp parse_offset(raw) do
    case Integer.parse(to_string(raw)) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, {:list_param_invalid, "offset must be a non-negative integer"}}
    end
  end
end
