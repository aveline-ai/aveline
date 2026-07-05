defmodule Aveline.DataSources do
  @moduledoc """
  External databases a workspace charts from (see `DataSource`).

  The adapter is derived from the URL scheme at create time
  (postgres:// or mysql://) — one fewer thing to pass, impossible to
  contradict. `safe_map/1` is the ONLY shape that leaves this module
  for read surfaces: name, adapter, host, database. The URL never does.
  """

  import Ecto.Query, warn: false

  alias Aveline.DataSources.DataSource
  alias Aveline.Repo

  defp base_query do
    from ds in DataSource, where: not ds.superseded and is_nil(ds.deleted_at)
  end

  def list_for_workspace(workspace_id) do
    from(ds in base_query(), where: ds.workspace_id == ^workspace_id, order_by: ds.name)
    |> Repo.all()
  end

  @doc """
  Live AND soft-deleted current versions — the audit view. A deleted
  source still holds its encrypted credential (that's what makes
  restore work), so the page humans audit must show it.
  """
  def list_all_for_workspace(workspace_id) do
    from(ds in DataSource,
      where: ds.workspace_id == ^workspace_id and not ds.superseded,
      order_by: ds.name,
      preload: [:created_by]
    )
    |> Repo.all()
  end

  def get_current_by_name(workspace_id, name) when is_binary(name) do
    from(ds in base_query(), where: ds.workspace_id == ^workspace_id and ds.name == ^name)
    |> Repo.one()
  end

  def get_current_by_base(base_id) when is_binary(base_id) do
    from(ds in base_query(), where: ds.base_data_source_id == ^base_id)
    |> Repo.one()
  end

  @doc """
  Latest version regardless of deletion — for echoing metadata on chart
  blocks whose source was deleted (same spirit as doc_link's dead-target
  echo).
  """
  def get_latest_by_base(base_id) when is_binary(base_id) do
    from(ds in DataSource, where: ds.base_data_source_id == ^base_id and not ds.superseded)
    |> Repo.one()
  end

  def create(workspace_id, name, url, created_by_id) do
    case adapter_from_url(url) do
      {:ok, adapter} ->
        %DataSource{}
        |> DataSource.create_changeset(%{
          workspace_id: workspace_id,
          base_data_source_id: Ecto.UUID.generate(),
          name: name,
          adapter: adapter,
          url: url,
          created_by_id: created_by_id
        })
        |> Repo.insert()

      {:error, msg} ->
        {:error, :invalid_data_source_url, msg}
    end
  end

  @doc """
  Soft-deletes the row, HARD-deletes the credential: the same update
  nulls the encrypted URL (constraint-enforced pairing). The audit
  trail keeps name/adapter/who/when; the secret is gone for good.
  There is no restore — connect a new source instead.
  """
  def delete(%DataSource{} = ds, user_id) do
    ds
    |> Ecto.Changeset.change(
      deleted_at: DateTime.utc_now(),
      deleted_by_id: user_id,
      url: nil
    )
    |> Repo.update()
  end

  @doc "The one shape read surfaces may see. Never the URL."
  def safe_map(%DataSource{} = ds) do
    uri = if ds.url, do: URI.parse(ds.url), else: %URI{}

    %{
      "name" => ds.name,
      "adapter" => ds.adapter,
      "host" => uri.host,
      "database" => uri.path && String.trim_leading(uri.path, "/"),
      "deleted" => not is_nil(ds.deleted_at),
      "created_at" => DateTime.to_iso8601(ds.inserted_at)
    }
  end

  defp adapter_from_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: s, host: h} when s in ["postgres", "postgresql"] and is_binary(h) ->
        {:ok, "postgres"}

      %URI{scheme: "mysql", host: h} when is_binary(h) ->
        {:ok, "mysql"}

      %URI{scheme: nil} ->
        {:error, "url must include a scheme: postgres://... or mysql://..."}

      %URI{scheme: s} ->
        {:error, "unsupported scheme #{inspect(s)}; expected postgres:// or mysql://"}
    end
  end

  defp adapter_from_url(_), do: {:error, "url must be a string"}
end
