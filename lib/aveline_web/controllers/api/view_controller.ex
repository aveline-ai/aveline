defmodule AvelineWeb.Api.ViewController do
  @moduledoc """
  Views — named, versioned snapshots of the Docs page's display knobs.
  Thin shell over the Gleam handlers (src/aveline/handlers/views.gleam,
  src/aveline/handlers/view_buckets.gleam): params in, typed request to
  the handler, envelope out. All decisions live in Gleam.
  """
  use AvelineWeb, :controller

  import Aveline.Gleam.Interop

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    views = :aveline@handlers@views.index(CtxBuilder.build(), CtxBuilder.scope(conn))
    Envelope.ok(conn, %{views: Enum.map(views, &view_json/1)})
  end

  def create(conn, params) do
    request =
      {:create_view_request, to_string(params["name"]), string_opt(params["description"]),
       config_param(params["config"]), bucket_choice(params["bucket"], :default_bucket)}

    CtxBuilder.build()
    |> :aveline@handlers@views.create(CtxBuilder.scope(conn), request)
    |> reply_view(conn)
  end

  def update(conn, %{"name" => name} = params) do
    request =
      {:update_view_request, name, truthy_string_opt(params["new_name"]),
       truthy_string_opt(params["description"]), update_config_param(params["config"])}

    CtxBuilder.build()
    |> :aveline@handlers@views.update(CtxBuilder.scope(conn), request)
    |> reply_view(conn)
  end

  def delete(conn, %{"name" => name}) do
    case :aveline@handlers@views.delete(CtxBuilder.build(), CtxBuilder.scope(conn), name) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  def restore(conn, %{"name" => name}) do
    CtxBuilder.build()
    |> :aveline@handlers@views.restore(CtxBuilder.scope(conn), name)
    |> reply_view(conn)
  end

  def pin(conn, %{"name" => name}), do: set_pin(conn, name, true)
  def unpin(conn, %{"name" => name}), do: set_pin(conn, name, false)

  defp set_pin(conn, name, pinned?) do
    CtxBuilder.build()
    |> :aveline@handlers@views.set_pinned(CtxBuilder.scope(conn), name, pinned?)
    |> reply_view(conn)
  end

  @doc """
  Move a view to another bucket. View owner only, into a bucket they
  can use. "yours" targets (and lazily creates) your personal bucket.
  """
  def move(conn, %{"name" => name, "bucket" => bucket_name}) do
    CtxBuilder.build()
    |> :aveline@handlers@views.move(
      CtxBuilder.scope(conn),
      name,
      bucket_choice(bucket_name, :default_bucket)
    )
    |> reply_view(conn)
  end

  def move(_conn, _params), do: {:error, {:missing_field, "bucket"}}

  # ===== Buckets (see the view-buckets TIP) =====

  @doc "Buckets you can use, each with its member list."
  def buckets(conn, _params) do
    buckets = :aveline@handlers@view_buckets.index(CtxBuilder.build(), CtxBuilder.scope(conn))
    Envelope.ok(conn, %{buckets: Enum.map(buckets, &bucket_json/1)})
  end

  @doc """
  Create a project bucket. Optional visibility: "private" (default,
  owner + members) | "workspace" (everyone).
  """
  def create_bucket(conn, %{"name" => name} = params) do
    CtxBuilder.build()
    |> :aveline@handlers@view_buckets.create(
      CtxBuilder.scope(conn),
      to_string(name),
      string_opt(params["visibility"])
    )
    |> reply_bucket(conn)
  end

  @doc "Change a project bucket's visibility in place. Owner only."
  def set_bucket_visibility(conn, %{"bucket_name" => name, "visibility" => vis}) do
    CtxBuilder.build()
    |> :aveline@handlers@view_buckets.set_visibility(CtxBuilder.scope(conn), name, to_string(vis))
    |> reply_bucket(conn)
  end

  def set_bucket_visibility(_conn, _params), do: {:error, {:missing_field, "visibility"}}

  @doc "Delete an empty project bucket. Owner only."
  def delete_bucket(conn, %{"bucket_name" => name}) do
    case :aveline@handlers@view_buckets.delete(CtxBuilder.build(), CtxBuilder.scope(conn), name) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  @doc "Add a workspace member to a project bucket. Owner only."
  def add_bucket_member(conn, %{"bucket_name" => name, "username" => username}) do
    CtxBuilder.build()
    |> :aveline@handlers@view_buckets.add_member(CtxBuilder.scope(conn), name, to_string(username))
    |> reply_membership(conn, name, username)
  end

  def add_bucket_member(_conn, _params), do: {:error, {:missing_field, "username"}}

  @doc "Remove a member from a project bucket. Owner only."
  def remove_bucket_member(conn, %{"bucket_name" => name, "username" => username}) do
    CtxBuilder.build()
    |> :aveline@handlers@view_buckets.remove_member(
      CtxBuilder.scope(conn),
      name,
      to_string(username)
    )
    |> reply_membership(conn, name, username)
  end

  # ===== Replies =====

  defp reply_view({:ok, view}, conn), do: Envelope.ok(conn, %{view: view_json(view)})
  defp reply_view({:error, err}, _conn), do: GleamAdapter.error(err)

  defp reply_bucket({:ok, bucket}, conn), do: Envelope.ok(conn, %{bucket: bucket_json(bucket)})
  defp reply_bucket({:error, err}, _conn), do: GleamAdapter.error(err)

  defp reply_membership({:ok, nil}, conn, bucket, username),
    do: Envelope.ok(conn, %{bucket: bucket, username: username})

  defp reply_membership({:error, err}, _conn, _bucket, _username), do: GleamAdapter.error(err)

  # ===== Params -> typed Gleam values =====

  defp string_opt(v) when is_binary(v), do: {:some, v}
  defp string_opt(nil), do: :none
  defp string_opt(_), do: {:some, ""}

  # The old controller used `if params[key]` — "" and other truthy
  # non-nil values counted as present.
  defp truthy_string_opt(v) when is_binary(v), do: {:some, v}
  defp truthy_string_opt(v) when v in [nil, false], do: :none
  defp truthy_string_opt(_), do: {:some, ""}

  defp bucket_choice(nil, default), do: default
  defp bucket_choice("yours", _default), do: :yours_bucket
  defp bucket_choice("team", _default), do: :team_bucket
  defp bucket_choice(name, _default) when is_binary(name), do: {:named_bucket, name}
  defp bucket_choice(_other, _default), do: {:named_bucket, ""}

  defp config_param(nil), do: :no_config
  defp config_param(false), do: :no_config
  defp config_param(map) when is_map(map), do: {:config_object, raw_config(map)}
  defp config_param(_), do: :not_an_object

  defp update_config_param(map) when is_map(map), do: {:config_object, raw_config(map)}
  defp update_config_param(v) when v in [nil, false], do: :no_config
  defp update_config_param(_), do: :not_an_object

  defp raw_config(map) do
    {:raw_config, raw_tags(map), raw_field(map, "group_by"), raw_field(map, "sub_group_by"),
     raw_field(map, "edited"), raw_field(map, "sort"), raw_field(map, "icon")}
  end

  defp raw_tags(map) do
    case Map.fetch(map, "tags") do
      :error ->
        :tags_absent

      {:ok, nil} ->
        {:tags_list, []}

      {:ok, list} when is_list(list) ->
        if Enum.all?(list, &is_binary/1),
          do: {:tags_list, list},
          else: {:tags_invalid, Enum.filter(list, &is_binary/1)}

      {:ok, _} ->
        {:tags_invalid, []}
    end
  end

  defp raw_field(map, key) do
    case Map.fetch(map, key) do
      :error -> :absent
      {:ok, nil} -> :null
      {:ok, v} when is_binary(v) -> {:raw_string, v}
      {:ok, _} -> :bad_field
    end
  end

  # ===== Gleam values -> JSON =====

  defp view_json(
         {:view, _id, _workspace_id, _base_view_id, version_number, name, description, config,
          pinned, _owner_id, bucket, created_at}
       ) do
    %{
      "name" => name,
      "description" => description,
      "config" => config_json(config),
      "pinned" => pinned,
      "bucket" => bucket_ref_json(bucket),
      "version_number" => version_number,
      "created_at" => created_at
    }
  end

  defp bucket_ref_json(:none), do: nil

  defp bucket_ref_json({:some, {:bucket, _id, _ws, name, kind, _vis, _owner}}),
    do: %{"name" => name, "kind" => kind_string(kind)}

  defp config_json({:view_config, tags, group_by, sub_group_by, edited, sort, icon}) do
    %{"tags" => tags}
    |> put_some("group_by", group_by)
    |> put_some("sub_group_by", sub_group_by)
    |> put_some("edited", edited)
    |> put_some("sort", sort)
    |> put_some("icon", icon)
  end

  defp put_some(map, _key, :none), do: map
  defp put_some(map, key, {:some, v}), do: Map.put(map, key, v)

  defp bucket_json({:bucket_summary, name, kind, visibility, owner, members}) do
    %{
      "name" => name,
      "kind" => kind_string(kind),
      "visibility" => visibility_string(visibility),
      "owner" => unopt(owner),
      "members" => Enum.map(members, &unopt/1)
    }
  end

  defp kind_string(:team), do: "team"
  defp kind_string(:personal), do: "personal"
  defp kind_string(:project), do: "project"

  defp visibility_string(:workspace_visible), do: "workspace"
  defp visibility_string(:private), do: "private"
end
