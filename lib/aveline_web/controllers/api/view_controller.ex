defmodule AvelineWeb.Api.ViewController do
  @moduledoc """
  Views — named, versioned snapshots of the Docs page's display knobs.
  Config tier: create / versioned edit / soft delete / restore, plus
  pin/unpin (placement, in-place). See `Aveline.Views`.
  """
  use AvelineWeb, :controller

  alias Aveline.Views
  alias AvelineWeb.Api.Envelope

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    Envelope.ok(conn, %{
      views:
        ws.id
        |> Views.list_for_workspace(viewer: user.id)
        |> Enum.map(&Views.safe_map/1)
    })
  end

  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user
    name = params["name"] |> to_string() |> String.trim() |> String.downcase()

    # Low-spam default: no bucket means YOUR bucket, not the team's.
    # Publishing to everyone is an explicit --bucket team.
    bucket_result =
      case params["bucket"] do
        nil -> {:ok, Views.ensure_personal_bucket(ws.id, user.id)}
        "yours" -> {:ok, Views.ensure_personal_bucket(ws.id, user.id)}
        "team" -> {:ok, Views.ensure_team_bucket(ws.id)}
        b -> fetch_bucket(ws, user, b)
      end

    with {:ok, bucket} <- bucket_result,
         {:ok, view} <-
           Views.create(ws.id, name, params["description"], params["config"] || %{}, user.id,
             bucket: bucket
           ) do
      Envelope.ok(conn, %{view: Views.safe_map(Aveline.Repo.preload(view, :bucket))})
    end
  end

  def update(conn, %{"name" => name} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    changes =
      %{}
      |> then(fn c -> if params["new_name"], do: Map.put(c, :name, params["new_name"]), else: c end)
      |> then(fn c ->
        if params["description"], do: Map.put(c, :description, params["description"]), else: c
      end)
      |> then(fn c -> if params["config"], do: Map.put(c, :config, params["config"]), else: c end)

    with {:ok, view} <- fetch_usable(ws, user, name),
         {:ok, view} <- Views.edit(view, changes, user.id) do
      Envelope.ok(conn, %{view: Views.safe_map(view)})
    end
  end

  def delete(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, view} <- fetch_usable(ws, user, name),
         {:ok, _} <- Views.delete(view, user.id) do
      Envelope.ok(conn, %{})
    end
  end

  def restore(conn, %{"name" => name}) do
    ws = conn.assigns.current_workspace

    with {:ok, view} <- Views.restore(ws.id, name) do
      Envelope.ok(conn, %{view: Views.safe_map(view)})
    end
  end

  def pin(conn, %{"name" => name}), do: set_pin(conn, name, true)
  def unpin(conn, %{"name" => name}), do: set_pin(conn, name, false)

  defp set_pin(conn, name, pinned?) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, view} <- fetch_usable(ws, user, name),
         {:ok, view} <- Views.set_pinned(view, pinned?) do
      Envelope.ok(conn, %{view: Views.safe_map(view)})
    end
  end

  # ===== Buckets (see the view-buckets TIP) =====

  @doc "Buckets you can use, each with its member list."
  def buckets(conn, _params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    buckets =
      ws.id
      |> Views.list_buckets_for(user.id)
      |> Enum.map(&bucket_map/1)

    Envelope.ok(conn, %{buckets: buckets})
  end

  @doc """
  Create a project bucket. Optional visibility: "private" (default,
  owner + members) | "workspace" (everyone).
  """
  def create_bucket(conn, %{"name" => name} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, bucket} <-
           Views.create_bucket(ws.id, name, user.id, visibility: params["visibility"]) do
      Envelope.ok(conn, %{bucket: bucket_map(bucket)})
    end
  end

  @doc "Change a project bucket's visibility in place. Owner only."
  def set_bucket_visibility(conn, %{"bucket_name" => name, "visibility" => vis}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, bucket} <- fetch_bucket(ws, user, name),
         {:ok, bucket} <- Views.set_bucket_visibility(bucket, vis, user.id) do
      Envelope.ok(conn, %{bucket: bucket_map(bucket)})
    end
  end

  def set_bucket_visibility(_conn, _params), do: {:error, {:missing_field, "visibility"}}

  @doc "Delete an empty project bucket. Owner only."
  def delete_bucket(conn, %{"bucket_name" => name}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, bucket} <- fetch_bucket(ws, user, name),
         {:ok, _} <- Views.delete_bucket(bucket, user.id) do
      Envelope.ok(conn, %{})
    end
  end

  @doc "Add a workspace member to a project bucket. Owner only."
  def add_bucket_member(conn, %{"bucket_name" => name, "username" => username}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, bucket} <- fetch_bucket(ws, user, name),
         %_{} = target <- Aveline.Accounts.get_user_by_username(username) || {:error, :not_member},
         {:ok, _} <- Views.add_bucket_member(bucket, target.id, user.id) do
      Envelope.ok(conn, %{bucket: name, username: username})
    end
  end

  def add_bucket_member(_conn, _params), do: {:error, {:missing_field, "username"}}

  @doc "Remove a member from a project bucket. Owner only."
  def remove_bucket_member(conn, %{"bucket_name" => name, "username" => username}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, bucket} <- fetch_bucket(ws, user, name),
         %_{} = target <- Aveline.Accounts.get_user_by_username(username) || {:error, :not_member},
         {:ok, _} <- Views.remove_bucket_member(bucket, target.id, user.id) do
      Envelope.ok(conn, %{bucket: name, username: username})
    end
  end

  @doc """
  Move a view to another bucket. View owner only, into a bucket they
  can use. "yours" targets (and lazily creates) your personal bucket.
  """
  def move(conn, %{"name" => name, "bucket" => bucket_name}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    bucket_result =
      case bucket_name do
        "yours" -> {:ok, Views.ensure_personal_bucket(ws.id, user.id)}
        "team" -> {:ok, Views.ensure_team_bucket(ws.id)}
        b -> fetch_bucket(ws, user, b)
      end

    with {:ok, view} <- fetch_usable(ws, user, name),
         {:ok, bucket} <- bucket_result,
         {:ok, view} <- Views.move_view(view, bucket, user.id) do
      Envelope.ok(conn, %{view: Views.safe_map(Aveline.Repo.preload(view, :bucket, force: true))})
    end
  end

  def move(_conn, _params), do: {:error, {:missing_field, "bucket"}}

  # ===== Helpers =====

  # One access rule for every by-name endpoint; inaccessible and
  # nonexistent are indistinguishable on purpose.
  defp fetch_usable(ws, user, name) do
    case Views.get_current_by_name(ws.id, name) do
      nil -> {:error, :not_found}
      view -> if Views.member_can_use?(view, user.id), do: {:ok, view}, else: {:error, :not_found}
    end
  end

  defp fetch_bucket(ws, user, name) do
    case Views.get_bucket(ws.id, name) do
      nil -> {:error, :not_found}
      b -> if Views.bucket_audience?(b, user.id), do: {:ok, b}, else: {:error, :not_found}
    end
  end

  defp bucket_map(bucket) do
    members =
      if bucket.kind == "project",
        do: Enum.map(Views.list_bucket_members(bucket), &(&1.user && &1.user.username)),
        else: []

    %{
      name: bucket.name,
      kind: bucket.kind,
      visibility: bucket.visibility,
      owner: bucket.owner_id && owner_username(bucket),
      members: members
    }
  end

  defp owner_username(bucket) do
    case Aveline.Repo.preload(bucket, :owner).owner do
      nil -> nil
      %{username: u} -> u
    end
  end
end
