defmodule AvelineWeb.Api.ViewController do
  use AvelineWeb, :controller

  alias Aveline.Views

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    views = Views.list_views(conn.assigns.current_workspace.id)

    conn
    |> put_view(json: AvelineWeb.Api.ViewJSON)
    |> render(:index, %{views: views})
  end

  def show(conn, %{"view_slug" => slug}) do
    ws = conn.assigns.current_workspace

    case Views.get_by_slug(ws.id, slug) do
      nil ->
        {:error, :not_found}

      view ->
        items = Views.matching_items(view)

        conn
        |> put_view(json: AvelineWeb.Api.ViewJSON)
        |> render(:show_with_items, %{view: view, items: items})
    end
  end

  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    attrs =
      params
      |> Map.take(["slug", "name", "tag_filter", "description"])
      |> Map.merge(%{
        "workspace_id" => ws.id,
        "created_by_id" => user.id
      })

    with {:ok, view} <- Views.create_view(attrs) do
      conn
      |> put_status(:created)
      |> put_view(json: AvelineWeb.Api.ViewJSON)
      |> render(:show, %{view: view})
    end
  end

  def update(conn, %{"view_slug" => slug} = params) do
    ws = conn.assigns.current_workspace

    with %_{} = view <- Views.get_active_by_slug(ws.id, slug) || {:error, :not_found},
         attrs = Map.take(params, ["name", "tag_filter", "description"]),
         {:ok, updated} <- Views.update_view(view, attrs) do
      conn
      |> put_view(json: AvelineWeb.Api.ViewJSON)
      |> render(:show, %{view: updated})
    end
  end

  def delete(conn, %{"view_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = view <- Views.get_active_by_slug(ws.id, slug) || {:error, :not_found},
         {:ok, deleted} <- Views.soft_delete_view(view, user.id) do
      conn
      |> put_view(json: AvelineWeb.Api.ViewJSON)
      |> render(:show, %{view: deleted})
    end
  end
end
