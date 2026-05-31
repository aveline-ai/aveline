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
        tags: combined_tags(params, view)
      ]

      items = Items.list_current(ws.id, opts)

      conn
      |> put_view(json: AvelineWeb.Api.ItemJSON)
      |> render(:index, %{items: items})
    end
  end

  def show(conn, %{"item_slug" => slug}) do
    ws = conn.assigns.current_workspace

    case Items.get_current_by_slug(ws.id, slug) do
      nil -> {:error, :not_found}
      item ->
        conn
        |> put_view(json: AvelineWeb.Api.ItemJSON)
        |> render(:show, %{item: item})
    end
  end

  @doc """
  Create a new item. Body:
    {
      "title": "...",
      "slug": "..." (optional, auto-derived from title),
      "summary": "...",
      "tags": [...],
      "pinned": false,
      "blocks": [...],
      "intent": "...",
      "actor": "human" | "agent"
    }
  """
  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    attrs = %{
      title: params["title"],
      slug: params["slug"],
      summary: params["summary"],
      tags: params["tags"] || [],
      pinned: !!params["pinned"],
      blocks: params["blocks"] || [],
      workspace_id: ws.id,
      owner_id: user.id,
      actor_user_id: user.id,
      actor_type: params["actor"] || "human",
      intent: params["intent"]
    }

    with {:ok, item} <- Items.create_item(attrs) do
      conn
      |> put_status(:created)
      |> put_view(json: AvelineWeb.Api.ItemJSON)
      |> render(:show, %{item: item})
    end
  end

  @doc """
  Apply an ops batch to an existing item. Body:
    {
      "intent": "...",
      "operations": [...],
      "resolves_comment_ids": [...] (optional),
      "actor": "human" | "agent",
      "title": "...",     (optional overrides)
      "summary": "...",
      "tags": [...],
      "pinned": false
    }
  """
  def update(conn, %{"item_slug" => slug} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = current <- Items.get_current_by_slug(ws.id, slug) || {:error, :not_found} do
      ops = params["operations"] || []
      intent = params["intent"]
      resolves = params["resolves_comment_ids"] || []

      update_attrs =
        %{
          actor_user_id: user.id,
          actor_type: params["actor"] || "human"
        }
        |> maybe_put(:title, params["title"])
        |> maybe_put(:summary, params["summary"])
        |> maybe_put(:tags, params["tags"])
        |> maybe_put(:pinned, params["pinned"])

      with {:ok, item} <-
             Items.apply_ops(current, ops, update_attrs,
               intent: intent,
               resolves_comment_ids: resolves
             ) do
        conn
        |> put_view(json: AvelineWeb.Api.ItemJSON)
        |> render(:show, %{item: item})
      end
    end
  end

  def delete(conn, %{"item_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = current <- Items.get_current_by_slug(ws.id, slug) || {:error, :not_found},
         {:ok, deleted} <- Items.soft_delete(current, user.id) do
      conn
      |> put_view(json: AvelineWeb.Api.ItemJSON)
      |> render(:show, %{item: deleted})
    end
  end

  def restore(conn, %{"item_slug" => slug}) do
    ws = conn.assigns.current_workspace

    # Find the base_item_id from any version with this slug
    case latest_for_slug(ws.id, slug) do
      nil ->
        {:error, :not_found}

      %{base_item_id: base} ->
        case Items.restore(base) do
          {:ok, item} ->
            conn
            |> put_view(json: AvelineWeb.Api.ItemJSON)
            |> render(:show, %{item: item})

          {:error, :not_user_deleted} ->
            {:error, :not_found}

          {:error, _} = err ->
            err
        end
    end
  end

  defp latest_for_slug(ws_id, slug) do
    import Ecto.Query

    Aveline.Repo.one(
      from i in Aveline.Items.Item,
        where: i.workspace_id == ^ws_id and i.slug == ^slug,
        order_by: [desc: i.version_number],
        limit: 1
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_pinned("true"), do: true
  defp parse_pinned(true), do: true
  defp parse_pinned("false"), do: false
  defp parse_pinned(false), do: false
  defp parse_pinned(_), do: nil

  defp combined_tags(params, view) do
    direct =
      case params["tag"] || params["tags"] do
        nil -> []
        list when is_list(list) -> list
        s when is_binary(s) -> String.split(s, ",", trim: true)
      end

    view_tags =
      case view do
        %Aveline.Views.View{tag_filter: tf} when is_list(tf) -> tf
        _ -> []
      end

    Enum.uniq(direct ++ view_tags)
  end

  defp resolve_view(_ws_id, nil), do: {:ok, nil}
  defp resolve_view(_ws_id, ""), do: {:ok, nil}

  defp resolve_view(ws_id, slug) do
    case Views.get_active_by_slug(ws_id, slug) do
      nil -> {:error, :not_found}
      v -> {:ok, v}
    end
  end
end
