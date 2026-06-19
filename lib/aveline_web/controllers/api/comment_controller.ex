defmodule AvelineWeb.Api.CommentController do
  use AvelineWeb, :controller

  alias Aveline.Docs
  alias Aveline.Comments

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, %{"doc_slug" => doc_slug}) do
    with %_{} = item <- resolve_current(conn, doc_slug) || {:error, :not_found} do
      # API always returns the snapshot of the CURRENT doc-version — same
      # as what the doc-show LV renders by default. Time-travel is web-UI
      # only for now.
      messages = Comments.list_for_doc_version(item.id)

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

  # `id` here is the LOGICAL (base) comment id. Edits insert a new
  # version and supersede the prior — author-only.
  def update(conn, %{"id" => base_id, "body" => body}) do
    user = conn.assigns.current_user

    with %_{} = current <- Comments.get_current_by_base(base_id) || {:error, :not_found},
         {:ok, new_v} <- Comments.edit_comment_body(current, body, user.id) do
      conn
      |> put_view(json: AvelineWeb.Api.CommentJSON)
      |> render(:show, %{message: new_v})
    else
      {:error, :forbidden} -> {:error, :forbidden}
      err -> err
    end
  end

  def delete(conn, %{"id" => base_id}) do
    user = conn.assigns.current_user

    with %_{} = msg <- Comments.get_current_by_base(base_id) || {:error, :not_found},
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
