defmodule AvelineWeb.Api.MessageController do
  use AvelineWeb, :controller

  alias Aveline.Items
  alias Aveline.Messages

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, %{"item_slug" => item_slug}) do
    with %_{} = item <- resolve_current(conn, item_slug) || {:error, :not_found} do
      messages = Messages.list_for_base_item(item.base_item_id)

      conn
      |> put_view(json: AvelineWeb.Api.MessageJSON)
      |> render(:index, %{messages: messages})
    end
  end

  def create(conn, %{"item_slug" => item_slug} = params) do
    user = conn.assigns.current_user

    with %_{} = item <- resolve_current(conn, item_slug) || {:error, :not_found},
         attrs = %{
           "item_id" => item.id,
           "block_id" => params["block_id"],
           "body" => params["body"],
           "actor_user_id" => user.id,
           "actor_type" => params["actor"] || "human"
         },
         {:ok, message} <- Messages.create_message(attrs) do
      conn
      |> put_status(:created)
      |> put_view(json: AvelineWeb.Api.MessageJSON)
      |> render(:show, %{message: message})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with %_{} = msg <- Messages.get_message(id) || {:error, :not_found},
         true <- is_nil(msg.deleted_at) || {:error, :not_found},
         {:ok, updated} <- Messages.update_message(msg, Map.take(params, ["body"])) do
      conn
      |> put_view(json: AvelineWeb.Api.MessageJSON)
      |> render(:show, %{message: updated})
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with %_{} = msg <- Messages.get_message(id) || {:error, :not_found},
         {:ok, deleted} <- Messages.soft_delete_message(msg, user.id) do
      conn
      |> put_view(json: AvelineWeb.Api.MessageJSON)
      |> render(:show, %{message: deleted})
    end
  end

  defp resolve_current(conn, slug) do
    ws = conn.assigns.current_workspace
    Items.get_current_by_slug(ws.id, slug)
  end
end
