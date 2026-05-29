defmodule AvelineWeb.Api.ItemController do
  use AvelineWeb, :controller

  alias Aveline.Items
  alias Aveline.Views

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, params) do
    ws = conn.assigns.current_workspace

    with {:ok, view} <- resolve_view(ws.id, params["view"]) do
      opts = [
        pinned: parse_pinned(params["pinned"]),
        tags: parse_tags(params),
        view: view
      ]

      items = Items.list_items(ws.id, opts)

      conn
      |> put_view(json: AvelineWeb.Api.ItemJSON)
      |> render(:index, %{items: items})
    end
  end

  def show(conn, %{"item_slug" => slug}) do
    ws = conn.assigns.current_workspace

    case Items.get_by_slug(ws.id, slug) do
      nil ->
        {:error, :not_found}

      item ->
        conn
        |> put_view(json: AvelineWeb.Api.ItemJSON)
        |> render(:show, %{item: item})
    end
  end

  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    attrs =
      params
      |> Map.take(["title", "body", "summary", "tags", "pinned", "slug"])
      |> Map.merge(%{
        "workspace_id" => ws.id,
        "owner_id" => user.id,
        "created_by_id" => user.id,
        "created_via" => "cli"
      })

    with {:ok, item} <- Items.create_item(attrs) do
      conn
      |> put_status(:created)
      |> put_view(json: AvelineWeb.Api.ItemJSON)
      |> render(:show, %{item: item})
    end
  end

  def update(conn, %{"item_slug" => slug} = params) do
    ws = conn.assigns.current_workspace

    with %_{} = item <- Items.get_active_by_slug(ws.id, slug) || {:error, :not_found},
         attrs = Map.take(params, ["title", "body", "summary", "tags", "pinned"]),
         {:ok, updated} <- Items.update_item(item, attrs) do
      conn
      |> put_view(json: AvelineWeb.Api.ItemJSON)
      |> render(:show, %{item: updated})
    end
  end

  def delete(conn, %{"item_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = item <- Items.get_active_by_slug(ws.id, slug) || {:error, :not_found},
         {:ok, deleted} <- Items.soft_delete_item(item, user.id) do
      conn
      |> put_view(json: AvelineWeb.Api.ItemJSON)
      |> render(:show, %{item: deleted})
    end
  end

  def restore(conn, %{"item_slug" => slug}) do
    ws = conn.assigns.current_workspace

    with %_{} = item <- Items.get_by_slug(ws.id, slug) || {:error, :not_found},
         {:ok, restored} <- Items.restore_item(item) do
      conn
      |> put_view(json: AvelineWeb.Api.ItemJSON)
      |> render(:show, %{item: restored})
    end
  end

  # ===== Helpers =====

  defp parse_pinned("true"), do: true
  defp parse_pinned(true), do: true
  defp parse_pinned("false"), do: false
  defp parse_pinned(false), do: false
  defp parse_pinned(_), do: nil

  # Accept ?tag=foo&tag=bar (Plug parses this as ["foo", "bar"] when same key
  # repeats only if `tag[]` is used; if not, Plug keeps the last. We accept
  # both `tag` and `tags` (comma-separated or list).
  defp parse_tags(params) do
    raw = params["tag"] || params["tags"] || []

    cond do
      is_list(raw) -> raw
      is_binary(raw) -> String.split(raw, ",", trim: true) |> Enum.map(&String.trim/1)
      true -> []
    end
  end

  defp resolve_view(_workspace_id, nil), do: {:ok, nil}
  defp resolve_view(_workspace_id, ""), do: {:ok, nil}

  defp resolve_view(workspace_id, slug) when is_binary(slug) do
    case Views.get_active_by_slug(workspace_id, slug) do
      nil -> {:error, :not_found}
      view -> {:ok, view}
    end
  end
end
