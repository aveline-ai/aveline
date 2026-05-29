defmodule AvelineWeb.Api.ViewController do
  use AvelineWeb, :controller

  alias Aveline.Views

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    views =
      case params["scope"] do
        "team" -> Views.list_team_views(ws.id)
        "personal" -> Views.list_personal_views(ws.id, user.id)
        _ -> Views.list_visible_views(ws.id, user.id)
      end

    conn
    |> put_view(json: AvelineWeb.Api.ViewJSON)
    |> render(:index, %{views: views})
  end

  def show(conn, %{"view_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with view when not is_nil(view) <- Views.get_by_slug(ws.id, slug),
         true <- Views.visible_to?(view, user.id) do
      items = Views.matching_items(view)

      conn
      |> put_view(json: AvelineWeb.Api.ViewJSON)
      |> render(:show_with_items, %{view: view, items: items})
    else
      _ -> {:error, :not_found}
    end
  end

  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    attrs =
      params
      |> Map.take(["slug", "name", "tag_filter", "description", "scope"])
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
    user = conn.assigns.current_user

    with %_{} = view <- Views.get_active_by_slug(ws.id, slug) || {:error, :not_found},
         true <- Views.visible_to?(view, user.id) || {:error, :not_found},
         attrs = Map.take(params, ["name", "tag_filter", "description", "scope"]),
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
         true <- Views.visible_to?(view, user.id) || {:error, :not_found},
         {:ok, deleted} <- Views.soft_delete_view(view, user.id) do
      conn
      |> put_view(json: AvelineWeb.Api.ViewJSON)
      |> render(:show, %{view: deleted})
    end
  end
end
