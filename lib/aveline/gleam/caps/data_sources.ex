defmodule Aveline.Gleam.Caps.DataSources do
  @moduledoc """
  Real IO for src/aveline/caps/data_sources.gleam. Keep field order in
  lockstep. The credential never leaves this module: the `Secret` the
  handler threads through is the raw request binary, and the query/edit
  closures re-read the row themselves to dial.
  """

  import Aveline.Gleam.Interop

  alias Aveline.DataSources
  alias Aveline.DataSources.DataSource
  alias Aveline.Repo

  def build do
    {:data_sources_caps,
     fn workspace_id ->
       workspace_id |> DataSources.list_for_workspace() |> Enum.map(&info/1)
     end,
     fn workspace_id, name ->
       workspace_id |> DataSources.get_current_by_name(name) |> opt(&info/1)
     end,
     fn workspace_id, name, template, password, user_id ->
       workspace_id
       |> DataSources.create(name, template, password, user_id)
       |> write_result()
     end,
     fn data_source_id, name, template, password, user_id ->
       ds = Repo.get!(DataSource, data_source_id)

       changes = %{name: name, url: template} |> put_password(password)

       ds
       |> DataSources.edit(changes, user_id)
       |> write_result()
     end,
     fn workspace_id, sql ->
       DataSources.Catalog.run(workspace_id, sql)
     end,
     fn data_source_id, sql ->
       DataSources.Runner.run(Repo.get!(DataSource, data_source_id), sql)
     end,
     fn data_source_id, user_id ->
       {:ok, _} = DataSources.delete(Repo.get!(DataSource, data_source_id), user_id)
       nil
     end}
  end

  defp put_password(changes, :none), do: changes
  defp put_password(changes, {:some, password}), do: Map.put(changes, :password, password)

  defp write_result({:ok, ds}), do: {:ok, info(ds)}

  defp write_result({:error, %Ecto.Changeset{errors: errors} = cs}) do
    if name_taken?(errors) do
      {:error, :ds_name_taken}
    else
      raise "unexpected data source changeset failure: #{inspect(cs.errors)}"
    end
  end

  # Coded context refusals (reserved_name, invalid_data_source_url,
  # password_required, workspace_source_immutable) echo verbatim so the
  # wire behavior can't drift from the pre-port context.
  defp write_result({:error, code, message}) when is_atom(code) and is_binary(message),
    do: {:error, {:ds_rejected, Atom.to_string(code), message}}

  defp name_taken?(errors) do
    Enum.any?([:workspace_id, :name], fn field ->
      case errors[field] do
        {_msg, opts} -> Keyword.get(opts, :constraint) == :unique
        _ -> false
      end
    end)
  end

  defp info(ds) do
    {:data_source_info, ds.id, ds.name, ds.adapter, ds.url_template, ds.version_number,
     credential(ds), not is_nil(ds.deleted_at), DateTime.to_iso8601(ds.inserted_at)}
  end

  defp credential(%DataSource{adapter: "workspace"}), do: :no_credential
  defp credential(%DataSource{password: p}) when is_binary(p), do: :live
  defp credential(_), do: :redacted
end
