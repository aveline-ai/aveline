defmodule Aveline.Gleam.Caps.Queries do
  @moduledoc """
  Real IO for src/aveline/caps/queries.gleam. Keep field order in
  lockstep. Reads reuse `Aveline.DataSources.Queries` (which stays the
  owner of the SQL); writes are one statement each so the Gleam handler
  owns the decision logic (validation, graph checks, versioning).
  """

  import Ecto.Query, warn: false
  import Aveline.Gleam.Interop

  alias Aveline.DataSources
  alias Aveline.DataSources.Engine
  alias Aveline.DataSources.Queries
  alias Aveline.DataSources.Query, as: Q
  alias Aveline.Repo

  def build do
    {:queries_caps,
     fn workspace_id ->
       workspace_id |> Queries.list_for_workspace() |> Enum.map(&to_gleam/1)
     end,
     fn workspace_id, source_base_id ->
       workspace_id
       |> Queries.list_for_source(source_base_id)
       |> Enum.map(&to_gleam/1)
     end,
     fn workspace_id, name ->
       workspace_id |> Queries.get_current_by_name(name) |> opt(&to_gleam/1)
     end,
     fn workspace_id, name ->
       workspace_id |> Queries.get_latest_deleted_by_name(name) |> opt(&to_gleam/1)
     end,
     fn workspace_id, name ->
       workspace_id
       |> DataSources.get_current_by_name(name)
       |> opt(fn s -> {:source_ref, s.base_data_source_id, s.adapter == "workspace"} end)
     end,
     &Engine.parse/1,
     &derived_edges/1,
     &with_graph_lock/2,
     &insert/2,
     &insert_next_version/4,
     &soft_delete/2,
     &restore/1}
  end

  # Every live derived query's (name, refs), parsed fresh. Catalogs are
  # small (dozens); recomputing beats storing derived state. A stored
  # query that no longer parses can't add edges — its own runs will
  # surface the error.
  defp derived_edges(workspace_id) do
    from(q in Q,
      where:
        not q.superseded and is_nil(q.deleted_at) and
          q.workspace_id == ^workspace_id and q.kind == "derived"
    )
    |> Repo.all()
    |> Enum.map(fn q ->
      case Engine.parse(q.sql) do
        {:ok, refs} -> {q.name, refs}
        {:error, _} -> {q.name, []}
      end
    end)
  end

  # The advisory lock serializes writers per workspace so two
  # concurrent edits can't each pass acyclicity against their own
  # snapshot. A Gleam Error rolls everything back.
  defp with_graph_lock(workspace_id, thunk) do
    Repo.transaction(
      fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext('aveline_queries:' || $1))", [
          workspace_id
        ])

        case thunk.() do
          {:ok, value} -> value
          {:error, err} -> Repo.rollback(err)
        end
      end,
      timeout: 30_000
    )
  end

  defp insert(workspace_id, {:new_query, name, description, kind, data_source_id, sql, user_id}) do
    %Q{}
    |> Q.insert_changeset(%{
      workspace_id: workspace_id,
      base_query_id: Ecto.UUID.generate(),
      name: name,
      description: unopt(description),
      kind: Atom.to_string(kind),
      data_source_id: unopt(data_source_id),
      sql: sql,
      created_by_id: user_id
    })
    |> Repo.insert()
    |> normalize()
  end

  # Runs inside with_graph_lock's transaction; on changeset error the
  # handler returns Error and the lock cap rolls the supersede back.
  defp insert_next_version(workspace_id, current, {:version_attrs, name, description, sql}, user_id) do
    {:query, id, base_query_id, version_number, _name, _desc, kind, data_source_id, _sql,
     _deleted, _created_at} = current

    {1, _} =
      from(q in Q, where: q.id == ^id)
      |> Repo.update_all(set: [superseded: true])

    %Q{}
    |> Q.insert_changeset(%{
      workspace_id: workspace_id,
      base_query_id: base_query_id,
      version_number: version_number + 1,
      name: name,
      description: unopt(description),
      kind: Atom.to_string(kind),
      data_source_id: unopt(data_source_id),
      sql: sql,
      created_by_id: user_id
    })
    |> Repo.insert()
    |> normalize()
  end

  defp soft_delete(query_id, user_id) do
    Repo.get!(Q, query_id)
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(), deleted_by_id: user_id)
    |> Repo.update!()
    |> to_gleam()
  end

  defp restore(query_id) do
    Repo.get!(Q, query_id)
    |> Ecto.Changeset.change(deleted_at: nil, deleted_by_id: nil)
    |> Ecto.Changeset.unique_constraint([:workspace_id, :name],
      name: :queries_workspace_id_name_index,
      message: "already exists"
    )
    |> Repo.update()
    |> normalize()
  end

  defp normalize({:ok, q}), do: {:ok, to_gleam(q)}

  defp normalize({:error, %Ecto.Changeset{} = cs}),
    do: {:error, Enum.map_join(cs.errors, "; ", fn {field, {m, _}} -> "#{field} #{m}" end)}

  defp to_gleam(%Q{} = q) do
    {:query, q.id, q.base_query_id, q.version_number, q.name, opt(q.description),
     kind_atom(q.kind), opt(q.data_source_id), q.sql, not is_nil(q.deleted_at),
     DateTime.to_iso8601(q.inserted_at)}
  end

  defp kind_atom("raw"), do: :raw
  defp kind_atom("derived"), do: :derived
end
