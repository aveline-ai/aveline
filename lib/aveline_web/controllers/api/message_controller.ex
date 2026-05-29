defmodule AvelineWeb.Api.MessageController do
  use AvelineWeb, :controller

  alias Aveline.Items
  alias Aveline.Messages

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, %{"item_slug" => item_slug}) do
    with %_{} = item <- resolve_item(conn, item_slug) || {:error, :not_found} do
      messages = Messages.list_for_item(item.id)

      conn
      |> put_view(json: AvelineWeb.Api.MessageJSON)
      |> render(:index, %{messages: messages})
    end
  end

  def create(conn, %{"item_slug" => item_slug} = params) do
    user = conn.assigns.current_user

    with %_{} = item <- resolve_item(conn, item_slug) || {:error, :not_found},
         attrs = build_attrs(params, item, user),
         {:ok, message} <- Messages.create_message(attrs) do
      conn
      |> put_status(:created)
      |> put_view(json: AvelineWeb.Api.MessageJSON)
      |> render(:show, %{message: message})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with %_{} = message <- Messages.get_message(id) || {:error, :not_found},
         true <- is_nil(message.deleted_at) || {:error, :not_found},
         attrs = Map.take(params, ["body"]),
         {:ok, updated} <- Messages.update_message(message, attrs) do
      conn
      |> put_view(json: AvelineWeb.Api.MessageJSON)
      |> render(:show, %{message: updated})
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with %_{} = message <- Messages.get_message(id) || {:error, :not_found},
         {:ok, deleted} <- Messages.soft_delete_message(message, user.id) do
      conn
      |> put_view(json: AvelineWeb.Api.MessageJSON)
      |> render(:show, %{message: deleted})
    end
  end

  defp resolve_item(conn, slug) do
    ws = conn.assigns.current_workspace
    Items.get_active_by_slug(ws.id, slug)
  end

  defp build_attrs(params, item, user) do
    params
    |> Map.take(["body"])
    |> Map.merge(%{
      "item_id" => item.id,
      "author_id" => user.id,
      "created_via" => Map.get(params, "created_via", "web")
    })
  end
end
