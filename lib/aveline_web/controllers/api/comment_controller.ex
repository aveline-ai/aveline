defmodule AvelineWeb.Api.CommentController do
  use AvelineWeb, :controller

  alias Aveline.Docs
  alias Aveline.Comments

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, %{"doc_slug" => doc_slug}) do
    with %_{} = item <- resolve_current(conn, doc_slug) || {:error, :not_found} do
      messages = Comments.list_for_base_doc(item.base_doc_id)

      conn
      |> put_view(json: AvelineWeb.Api.CommentJSON)
      |> render(:index, %{messages: messages})
    end
  end

  def create(conn, %{"doc_slug" => doc_slug} = params) do
    user = conn.assigns.current_user

    with %_{} = item <- resolve_current(conn, doc_slug) || {:error, :not_found},
         attrs = %{
           "doc_id" => item.id,
           "block_id" => params["block_id"],
           "body" => params["body"],
           "actor_user_id" => user.id,
           "actor_type" => params["actor"] || "human"
         },
         {:ok, message} <- Comments.create_comment(attrs) do
      conn
      |> put_status(:created)
      |> put_view(json: AvelineWeb.Api.CommentJSON)
      |> render(:show, %{message: message})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with %_{} = msg <- Comments.get_comment(id) || {:error, :not_found},
         true <- is_nil(msg.deleted_at) || {:error, :not_found},
         {:ok, updated} <- Comments.update_comment(msg, Map.take(params, ["body"])) do
      conn
      |> put_view(json: AvelineWeb.Api.CommentJSON)
      |> render(:show, %{message: updated})
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with %_{} = msg <- Comments.get_comment(id) || {:error, :not_found},
         {:ok, deleted} <- Comments.soft_delete_comment(msg, user.id) do
      conn
      |> put_view(json: AvelineWeb.Api.CommentJSON)
      |> render(:show, %{message: deleted})
    end
  end

  defp resolve_current(conn, slug) do
    ws = conn.assigns.current_workspace
    Docs.get_current_by_slug(ws.id, slug)
  end
end
