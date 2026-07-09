defmodule Aveline.DataSources do
  @moduledoc """
  External databases a workspace charts from (see `DataSource`).

  Input is two values: a connection-string TEMPLATE carrying a literal
  `<password>` placeholder (exactly once — validated), and the password
  itself. The template is public within the workspace and rendered
  verbatim on every read surface; the password is encrypted at rest,
  write-only (no read path exists, by design), and scrubbed the moment
  its row stops being live.

  Editing rules:
    * changing the template requires re-supplying the password — a
      stored secret may never be combined with connection parameters it
      wasn't written with (closes the classic edit-the-host-and-beacon
      exfiltration)
    * password-only rotation is allowed alone: new secret, unchanged
      destination, nothing to exfiltrate
    * rename alone is fine: it doesn't touch dialing

  `dial_url/1` substitutes the URL-encoded password into the template
  at query time, in memory only.
  """

  import Ecto.Query, warn: false

  alias Aveline.DataSources.DataSource
  alias Aveline.Repo

  @placeholder DataSource.placeholder()

  defp base_query do
    from ds in DataSource, where: not ds.superseded and is_nil(ds.deleted_at)
  end

  def list_for_workspace(workspace_id) do
    from(ds in base_query(), where: ds.workspace_id == ^workspace_id, order_by: ds.name)
    |> Repo.all()
  end

  @doc """
  Live AND soft-deleted current versions — the audit view. Deleted rows
  keep their template (it holds no secret) so the page can still say
  what they pointed at; their password was destroyed at delete time.
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
  The built-in catalog source (adapter \"workspace\", named \"derived\").
  Fetched by adapter, not name, so call sites don't hardcode the name.
  """
  def workspace_source(workspace_id) do
    from(ds in base_query(),
      where: ds.workspace_id == ^workspace_id and ds.adapter == "workspace"
    )
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

  def create(_workspace_id, name, _template, _password, _user_id)
      when name in ["derived", "workspace"] do
    {:error, :reserved_name,
     "#{inspect(name)} is reserved for the built-in catalog source — pick another"}
  end

  def create(workspace_id, name, template, password, created_by_id)
      when is_binary(password) do
    case validate_template(template) do
      {:ok, adapter} ->
        %DataSource{}
        |> DataSource.insert_changeset(%{
          workspace_id: workspace_id,
          base_data_source_id: Ecto.UUID.generate(),
          name: name,
          adapter: adapter,
          url_template: template,
          password: password,
          created_by_id: created_by_id
        })
        |> Repo.insert()

      {:error, msg} ->
        {:error, :invalid_data_source_url, msg}
    end
  end

  def create(_ws, _name, _template, _password, _user),
    do: {:error, :invalid_data_source_url, "password is required (pass \"\" for passwordless databases)"}

  @doc """
  Versioned edit. `changes` may carry `:name`, `:url` (template), and
  `:password`. Template changes REQUIRE `:password` (see moduledoc);
  password or name changes are fine alone. Mints v+1 on the same base
  id and scrubs the superseded row's secret in the same transaction.
  """
  def edit(%DataSource{adapter: "workspace"}, _changes, _user_id) do
    {:error, :workspace_source_immutable,
     "the workspace source is built in — it can't be renamed or repointed"}
  end

  def edit(%DataSource{} = current, changes, user_id) when is_map(changes) do
    template = Map.get(changes, :url, current.url_template)
    template_changed? = template != current.url_template

    cond do
      template_changed? and not is_binary(Map.get(changes, :password)) ->
        {:error, :password_required,
         "changing the connection template requires supplying the password with it — a stored secret is never combined with connection settings it wasn't written with"}

      true ->
        with {:ok, adapter} <- validate_template_or_invalid(template) do
          insert_next_version(current, %{
            name: Map.get(changes, :name, current.name),
            adapter: adapter,
            url_template: template,
            password: Map.get(changes, :password, current.password)
          }, user_id)
        end
    end
  end

  defp insert_next_version(current, attrs, user_id) do
    Repo.transaction(fn ->
      # Supersede AND scrub the old row's secret first — the partial
      # unique on base id demands supersede-before-insert, the CHECK
      # demands the scrub ride along.
      {1, _} =
        from(ds in DataSource, where: ds.id == ^current.id)
        |> Repo.update_all(set: [superseded: true, password: nil])

      insert =
        %DataSource{}
        |> DataSource.insert_changeset(%{
          workspace_id: current.workspace_id,
          base_data_source_id: current.base_data_source_id,
          version_number: current.version_number + 1,
          name: attrs.name,
          adapter: attrs.adapter,
          url_template: attrs.url_template,
          password: attrs.password,
          created_by_id: user_id
        })
        |> Repo.insert()

      case insert do
        {:ok, ds} -> ds
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  @doc """
  Soft-deletes the row, HARD-deletes the secret in the same update
  (constraint-enforced pairing). The template stays for audit; the
  password is gone for good. No restore — connect a new source.
  """
  def delete(%DataSource{adapter: "workspace"}, _user_id) do
    {:error, :workspace_source_immutable,
     "the workspace source is built in — it can't be deleted"}
  end

  def delete(%DataSource{} = ds, user_id) do
    ds
    |> Ecto.Changeset.change(
      deleted_at: DateTime.utc_now(),
      deleted_by_id: user_id,
      password: nil
    )
    |> Repo.update()
  end

  @doc """
  Seed the built-in workspace source (adapter "workspace") — the
  virtual source whose tables are the query catalog. Called at
  workspace creation; the query_catalog migration backfilled existing
  workspaces. Credential-less by design and CHECK-exempted.
  """
  def ensure_workspace_source(workspace_id) do
    case workspace_source(workspace_id) do
      nil ->
        %DataSource{}
        |> DataSource.insert_changeset(%{
          workspace_id: workspace_id,
          base_data_source_id: Ecto.UUID.generate(),
          name: "derived",
          adapter: "workspace",
          url_template: "workspace://catalog"
        })
        |> Repo.insert()

      ds ->
        {:ok, ds}
    end
  end

  @doc """
  The engine/dialect label shown to users. The workspace source's
  internal adapter is \"workspace\", but the engine it actually runs is
  DuckDB — so it reads consistently alongside postgres/mysql/redshift.
  """
  def dialect_label("workspace"), do: "duckdb"
  def dialect_label(adapter) when is_binary(adapter), do: adapter

  @doc """
  The one shape read surfaces may see. `url` is the TEMPLATE — the
  `<password>` placeholder renders as its own mask; the secret never
  appears anywhere.
  """
  def safe_map(%DataSource{adapter: "workspace"} = ds) do
    %{
      "name" => ds.name,
      "adapter" => ds.adapter,
      "url" => ds.url_template,
      "version_number" => ds.version_number,
      # "redacted" is the wire signal for deleted; the built-in source
      # never had a credential to lose.
      "credential" => "none",
      "built_in" => true,
      "deleted" => not is_nil(ds.deleted_at),
      "created_at" => DateTime.to_iso8601(ds.inserted_at)
    }
  end

  def safe_map(%DataSource{} = ds) do
    %{
      "name" => ds.name,
      "adapter" => ds.adapter,
      "url" => ds.url_template,
      "version_number" => ds.version_number,
      "credential" => if(ds.password, do: "live", else: "redacted"),
      "deleted" => not is_nil(ds.deleted_at),
      "created_at" => DateTime.to_iso8601(ds.inserted_at)
    }
  end

  @doc """
  The real connection URL — password URL-encoded and substituted into
  the template. Exists in memory for the duration of a query run and
  nowhere else. Only live rows have a password (constraint), so this is
  only called on them.
  """
  def dial_url(%DataSource{url_template: template, password: password})
      when is_binary(password) do
    String.replace(template, @placeholder, URI.encode_www_form(password))
  end

  # ===== template validation =====

  defp validate_template_or_invalid(template) do
    case validate_template(template) do
      {:ok, adapter} -> {:ok, adapter}
      {:error, msg} -> {:error, :invalid_data_source_url, msg}
    end
  end

  defp validate_template(template) when is_binary(template) do
    placeholder_count =
      template |> String.split(@placeholder) |> length() |> Kernel.-(1)

    cond do
      placeholder_count != 1 ->
        {:error,
         "template must contain the literal #{@placeholder} placeholder exactly once (the real password is passed separately and stored encrypted)"}

      true ->
        case URI.parse(template) do
          %URI{scheme: s, host: h} when s in ["postgres", "postgresql"] and is_binary(h) and h != "" ->
            {:ok, "postgres"}

          %URI{scheme: "mysql", host: h} when is_binary(h) and h != "" ->
            {:ok, "mysql"}

          # Postgres wire protocol, Redshift dialect. Dialed with the
          # postgres driver; stored distinctly for honest display and
          # dialect-aware formatting.
          %URI{scheme: "redshift", host: h} when is_binary(h) and h != "" ->
            {:ok, "redshift"}

          %URI{scheme: nil} ->
            {:error, "template must include a scheme: postgres://... or mysql://..."}

          %URI{scheme: s} when s in ["postgres", "postgresql", "mysql"] ->
            {:error, "template must include a host"}

          %URI{scheme: s} ->
            {:error, "unsupported scheme #{inspect(s)}; expected postgres://, mysql://, or redshift://"}
        end
    end
  end

  defp validate_template(_), do: {:error, "template must be a string"}
end
