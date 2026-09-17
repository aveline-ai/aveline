defmodule AvelineWeb.Api.FeDocsController do
  @moduledoc """
  Read-only endpoints for the Elm Docs page (fe-docs-list port of
  WorkspaceShowLive). Two things the LiveView assembled server-side
  that the public GET /docs shape doesn't carry:

    * `index` — the doc list enriched with the card fields the page
      renders (visibility, actor, per-doc view/kudos counts) plus a
      `has_more` flag (server fetches limit+1, same trick as the LV)
      and `total`, the filtered corpus size, for "shown of total".

      With `group=<scope>` the page is grouped server-side: one
      `{key, docs, has_more, total}` entry per scope member that has
      docs (registry order) plus a trailing `key: null` entry for docs
      carrying none of the members — each paginated independently, so
      a column is never a slice of a global page. Adding `key=<slug>`
      (or `key=none` for the unassigned column) with `offset` pages one
      column and answers in the flat `{docs, has_more, total}` shape.
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
  alias Aveline.Tags
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
      opts = filter_opts(conn, params) ++ [sort: sort]

      case parse_group(ws.id, params["group"], params["key"]) do
        {:ok, nil} ->
          Envelope.ok(conn, page(ws.id, opts, limit, offset))

        {:ok, {:all, members}} ->
          groups =
            (Enum.map(members, &{:member, &1}) ++ [{:unassigned, members}])
            |> Enum.map(fn group ->
              page(ws.id, opts ++ [group: group], limit, 0)
              |> Map.put(:key, group_key(group))
            end)
            |> Enum.reject(&(&1.docs == []))

          Envelope.ok(conn, %{
            groups: groups,
            total: groups |> Enum.map(& &1.total) |> Enum.sum()
          })

        {:ok, {:one, group}} ->
          Envelope.ok(conn, page(ws.id, opts ++ [group: group], limit, offset))

        {:error, _} = err ->
          err
      end
    end
  end

  # One page of the (possibly group-narrowed) list, plus the total the
  # page is a slice of. Fetches limit+1 to learn has_more without a
  # second round trip; the count is what the header shows.
  defp page(ws_id, opts, limit, offset) do
    raw = Docs.list_current(ws_id, opts ++ [limit: limit + 1, offset: offset])

    {items, has_more?} =
      case raw do
        list when length(list) > limit -> {Enum.take(list, limit), true}
        list -> {list, false}
      end

    base_ids = Enum.map(items, & &1.base_doc_id)
    view_counts = DocViews.counts_by_base(base_ids)
    kudos_counts = Kudos.counts_by_base(base_ids)

    %{
      docs: Enum.map(items, &card_map(&1, view_counts, kudos_counts)),
      has_more: has_more?,
      total: Docs.count_current(ws_id, opts)
    }
  end

  defp group_key({:member, slug}), do: slug
  defp group_key({:unassigned, _}), do: nil

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

  # `group` is a tag scope ("status"); `key` picks one of its columns.
  # A scope with no live members still groups: everything lands in the
  # unassigned column, which is what the client would render too.
  defp parse_group(_ws_id, nil, _key), do: {:ok, nil}
  defp parse_group(_ws_id, "", _key), do: {:ok, nil}

  defp parse_group(ws_id, scope, key) when is_binary(scope) do
    members = Tags.list_scope_members(ws_id, scope)

    case key do
      nil ->
        {:ok, {:all, members}}

      "" ->
        {:ok, {:all, members}}

      "none" ->
        {:ok, {:one, {:unassigned, members}}}

      slug ->
        if slug in members do
          {:ok, {:one, {:member, slug}}}
        else
          {:error, {:list_param_invalid, "key must be a member of the #{scope} scope or none"}}
        end
    end
  end

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
