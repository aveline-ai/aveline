defmodule AvelineWeb.Api.DocController do
  use AvelineWeb, :controller

  alias Aveline.Docs
  alias Aveline.Views

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, params) do
    ws = conn.assigns.current_workspace

    with {:ok, view} <- resolve_view(ws.id, params["view"]) do
      opts = [
        pinned: parse_pinned(params["pinned"]),
        tags: combined_tags(params, view)
      ]

      items = Docs.list_current(ws.id, opts)

      conn
      |> put_view(json: AvelineWeb.Api.DocJSON)
      |> render(:index, %{items: items})
    end
  end

  def show(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace

    case Docs.get_current_by_slug(ws.id, slug) do
      nil -> {:error, :not_found}
      item ->
        conn
        |> put_view(json: AvelineWeb.Api.DocJSON)
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

    with {:ok, item} <- Docs.create_doc(attrs) do
      conn
      |> put_status(:created)
      |> put_view(json: AvelineWeb.Api.DocJSON)
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
  def update(conn, %{"doc_slug" => slug} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = current <- Docs.get_current_by_slug(ws.id, slug) || {:error, :not_found} do
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
             Docs.apply_ops(current, ops, update_attrs,
               intent: intent,
               resolves_comment_ids: resolves
             ) do
        conn
        |> put_view(json: AvelineWeb.Api.DocJSON)
        |> render(:show, %{item: item})
      end
    end
  end

  def delete(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = current <- Docs.get_current_by_slug(ws.id, slug) || {:error, :not_found},
         {:ok, deleted} <- Docs.soft_delete(current, user.id) do
      conn
      |> put_view(json: AvelineWeb.Api.DocJSON)
      |> render(:show, %{item: deleted})
    end
  end

  def restore(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace

    # Find the base_doc_id from any version with this slug
    case latest_for_slug(ws.id, slug) do
      nil ->
        {:error, :not_found}

      %{base_doc_id: base} ->
        case Docs.restore(base) do
          {:ok, item} ->
            conn
            |> put_view(json: AvelineWeb.Api.DocJSON)
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
      from i in Aveline.Docs.Doc,
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
