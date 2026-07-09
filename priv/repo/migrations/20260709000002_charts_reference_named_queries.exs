defmodule Aveline.Repo.Migrations.ChartsReferenceNamedQueries do
  @moduledoc """
  Named-only charts: every current doc's inline chart SQL becomes a
  named catalog query, and the chart block is rewritten to reference it
  (`query_ref`). Inline SQL is retired as an authoring shape.

  One-time, forward-only, idempotent (a re-run finds no inline charts).
  Historical doc versions keep their inline blocks and still render via
  the legacy path — only *current* docs are rewritten.

  This drives the app contexts (creating queries + doc versions), which
  is unusual for a migration but fine here: `Queries.create` and
  `Docs.replace_blocks` need only the Repo (the engine spawns an OS
  process; the doc broadcast no-ops when PubSub is down — see
  Broadcasts). Defensive: any chart it can't convert (source gone,
  derived SQL that won't parse) is left as legacy inline.
  """
  use Ecto.Migration

  import Ecto.Query

  alias Aveline.DataSources.DataSource
  alias Aveline.DataSources.Queries
  alias Aveline.Docs
  alias Aveline.Repo

  def up do
    # Resolving a data source's name via the context loads its (encrypted)
    # password field, so the Cloak vault must be up. It already is when
    # this runs inside the app (dev server, release migrate); start it
    # for a cold `mix ecto.migrate` too. PubSub isn't needed — the doc
    # broadcast no-ops when it's down.
    ensure_vault!()

    Repo.all(from w in "workspaces", select: type(w.id, Ecto.UUID))
    |> Enum.each(&convert_workspace/1)
  end

  defp ensure_vault! do
    case Aveline.Vault.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise "could not start Aveline.Vault for the chart migration: #{inspect(reason)}"
    end
  end

  def down, do: :ok

  defp convert_workspace(workspace_id) do
    # The workspace source's base id — selected without the encrypted
    # password field, so we don't need the Cloak vault (not started
    # during migrate).
    ws_base =
      Repo.one(
        from d in DataSource,
          where:
            d.workspace_id == ^workspace_id and d.adapter == "workspace" and not d.superseded,
          select: d.base_data_source_id
      )

    workspace_id
    |> Docs.list_current()
    |> Enum.each(fn doc -> convert_doc(doc, workspace_id, ws_base) end)
  end

  # A live source's name by base id — name only, no encrypted password.
  defp source_name(base_id) do
    Repo.one(
      from d in DataSource,
        where: d.base_data_source_id == ^base_id and not d.superseded and is_nil(d.deleted_at),
        select: d.name
    )
  end

  defp inline?(b) do
    is_map(b) and b["type"] == "chart" and is_binary(b["data_source_id"]) and
      is_binary(b["query"]) and not is_map_key(b, "query_ref")
  end

  defp convert_doc(doc, workspace_id, ws_base) do
    if Enum.any?(doc.blocks || [], &inline?/1) do
      {new_blocks, _n} =
        Enum.map_reduce(doc.blocks, 0, fn block, n ->
          if inline?(block) do
            case convert_chart(block, doc, n, workspace_id, ws_base) do
              {:ok, rewritten} -> {rewritten, n + 1}
              :skip -> {block, n + 1}
            end
          else
            {block, n}
          end
        end)

      if new_blocks != doc.blocks do
        cleaned = Enum.map(new_blocks, fn b -> Map.drop(b, ["result", "source", "query_sql"]) end)

        Docs.replace_blocks(doc, cleaned, %{actor_user_id: doc.owner_id, actor_type: "agent"},
          intent: "migrate inline charts to named catalog queries"
        )
      end
    end
  end

  defp convert_chart(block, doc, n, workspace_id, ws_base) do
    base_id = block["data_source_id"]
    sql = block["query"]
    viz = block["viz"] || %{"type" => "table"}
    name = query_name(workspace_id, doc.slug, n)

    attrs =
      if ws_base && base_id == ws_base do
        %{name: name, sql: sql}
      else
        case source_name(base_id) do
          nil -> nil
          source_name -> %{name: name, source: source_name, sql: sql}
        end
      end

    with %{} = attrs <- attrs,
         {:ok, _query} <- Queries.create(workspace_id, attrs, doc.owner_id) do
      {:ok, %{"type" => "chart", "id" => block["id"], "query_ref" => name, "viz" => viz}}
    else
      _ -> :skip
    end
  end

  # doc-slug-derived, sanitized to the query name charset, uniquified.
  defp query_name(workspace_id, slug, n) do
    base =
      (slug || "chart")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.replace(~r/^[^a-z]+/, "")
      |> String.slice(0, 30)
      |> then(fn s -> if s == "", do: "chart", else: s end)

    uniquify(workspace_id, "#{base}_#{n + 1}", 0)
  end

  defp uniquify(workspace_id, candidate, suffix) do
    name = if suffix == 0, do: candidate, else: "#{candidate}_#{suffix}"

    case Queries.get_current_by_name(workspace_id, name) do
      nil -> name
      _ -> uniquify(workspace_id, candidate, suffix + 1)
    end
  end
end
