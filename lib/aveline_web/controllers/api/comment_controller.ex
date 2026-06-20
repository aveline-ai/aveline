defmodule AvelineWeb.Api.CommentController do
  @moduledoc """
  Comment lifecycle. Every write path calls the same `Aveline.Comments.*`
  context functions the LiveView calls. Reads return the current-doc-
  version snapshot (matches the LV default; time-travel is web-UI
  only for now).

  IDs in URL paths and request bodies are always the LOGICAL
  `base_comment_id` — the stable id that survives edits + reanchors.
  """
  use AvelineWeb, :controller

  alias Aveline.Comments
  alias Aveline.Docs
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  # ===== Reads =====

  def index(conn, %{"doc_slug" => doc_slug}) do
    with %_{} = item <- resolve_current(conn, doc_slug) || {:error, :not_found} do
      messages = Comments.list_for_doc_version(item.id)
      Envelope.ok(conn, %{comments: Enum.map(messages, &Views.comment/1)})
    end
  end

  # ===== Writes =====

  @doc """
  Post a new comment.

  Body:
      {
        "body": "...",
        "block_id": "b_xxx",          // optional; omit for doc-level
        "parent_comment_id": "...",   // optional; for replies
        "actor": "human" | "agent"    // defaults to "agent" for API
      }

  Echoes the new `id` (base_comment_id) so the agent can reply / edit /
  resolve / delete it without re-querying.
  """
  def create(conn, %{"doc_slug" => doc_slug} = params) do
    user = conn.assigns.current_user

    with %_{} = item <- resolve_current(conn, doc_slug) || {:error, :not_found},
         attrs = %{
           "doc_id" => item.id,
           "block_id" => params["block_id"],
           "parent_comment_id" => params["parent_comment_id"],
           "body" => params["body"],
           "actor_user_id" => user.id,
           "actor_type" => params["actor"] || "agent"
         },
         {:ok, message} <- Comments.create_comment(attrs) do
      Envelope.ok(conn, %{id: message.base_comment_id})
    end
  end

  @doc """
  Edit a comment body. Inserts a new comment-version row carrying
  state forward. Author-only.

  Path: `/comments/:id` where `id` is the base_comment_id.
  Body: `{"body": "new text"}`.
  """
  def update(conn, %{"id" => base_id, "body" => body}) do
    user = conn.assigns.current_user

    with %_{} = current <- Comments.get_current_by_base(base_id) || {:error, :not_found},
         true <- current.actor_user_id == user.id || {:error, :forbidden},
         {:ok, _new_v} <- Comments.edit_comment_body(current, body, user.id) do
      Envelope.ok(conn, %{})
    else
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, _} = err -> err
    end
  end

  def delete(conn, %{"id" => base_id}) do
    user = conn.assigns.current_user

    with %_{} = msg <- Comments.get_current_by_base(base_id) || {:error, :not_found},
         true <- msg.actor_user_id == user.id || {:error, :forbidden},
         {:ok, _} <- Comments.soft_delete_comment(msg, user.id) do
      Envelope.ok(conn, %{})
    end
  end

  def undelete(conn, %{"id" => base_id}) do
    user = conn.assigns.current_user

    with %_{} = msg <- Comments.get_latest_by_base(base_id) || {:error, :not_found},
         true <- msg.actor_user_id == user.id || {:error, :forbidden},
         {:ok, _} <- Comments.undelete_comment(msg) do
      Envelope.ok(conn, %{})
    end
  end

  @doc """
  Mark a thread resolved. For agent-driven resolution as part of a
  doc-version transition, prefer the disposition flow on
  `PATCH /docs/:slug` — that posts a reply comment in the same
  transaction and pins it to the new doc-version.
  This endpoint is the human-equivalent: standalone resolve.
  """
  def resolve(conn, %{"id" => base_id}) do
    user = conn.assigns.current_user

    with %_{} = msg <- Comments.get_current_by_base(base_id) || {:error, :not_found},
         {:ok, _} <- Comments.resolve_comment(msg, user.id) do
      Envelope.ok(conn, %{})
    end
  end

  def unresolve(conn, %{"id" => base_id}) do
    with %_{} = msg <- Comments.get_current_by_base(base_id) || {:error, :not_found},
         {:ok, _} <- Comments.unresolve_comment(msg) do
      Envelope.ok(conn, %{})
    end
  end

  # ===== Helpers =====

  defp resolve_current(conn, slug) do
    ws = conn.assigns.current_workspace
    Docs.get_current_by_slug(ws.id, slug)
  end
end
