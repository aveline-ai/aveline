defmodule AvelineWeb.Api.CommentController do
  @moduledoc """
  Comment lifecycle. All decisions live in the Gleam handler
  (src/aveline/handlers/comments.gleam) — this module only converts
  params to typed requests and renders results.

  IDs in URL paths and request bodies are always the LOGICAL
  `base_comment_id` — the stable id that survives edits + reanchors.
  """
  use AvelineWeb, :controller

  import Aveline.Gleam.Interop, only: [opt: 1, unopt: 1]

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  # ===== Reads =====

  def index(conn, %{"doc_slug" => doc_slug}) do
    case :aveline@handlers@comments.index(CtxBuilder.build(), CtxBuilder.scope(conn), doc_slug) do
      {:ok, comments} ->
        Envelope.ok(conn, %{comments: Enum.map(comments, &render_comment/1)})

      {:error, err} ->
        GleamAdapter.error(err)
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
    request =
      {:create_request, str_opt(params["body"]), opt(params["block_id"]),
       opt(params["parent_comment_id"]), opt(params["actor"])}

    case :aveline@handlers@comments.create(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           doc_slug,
           request
         ) do
      {:ok, id} -> Envelope.ok(conn, %{id: id})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  @doc """
  Edit a comment body. Inserts a new comment-version row carrying
  state forward. Author-only.

  Path: `/comments/:id` where `id` is the base_comment_id.
  Body: `{"body": "new text"}`.
  """
  def update(conn, %{"id" => base_id, "body" => body}) do
    run(conn, fn ctx, scope ->
      :aveline@handlers@comments.update(ctx, scope, base_id, str_opt(body))
    end)
  end

  def delete(conn, %{"id" => base_id}) do
    run(conn, fn ctx, scope -> :aveline@handlers@comments.delete(ctx, scope, base_id) end)
  end

  def undelete(conn, %{"id" => base_id}) do
    run(conn, fn ctx, scope -> :aveline@handlers@comments.undelete(ctx, scope, base_id) end)
  end

  @doc """
  Mark a thread resolved. For agent-driven resolution as part of a
  doc-version transition, prefer the disposition flow on
  `PATCH /docs/:slug` — that posts a reply comment in the same
  transaction and pins it to the new doc-version.
  This endpoint is the human-equivalent: standalone resolve.
  """
  def resolve(conn, %{"id" => base_id}) do
    run(conn, fn ctx, scope -> :aveline@handlers@comments.resolve(ctx, scope, base_id) end)
  end

  def unresolve(conn, %{"id" => base_id}) do
    run(conn, fn ctx, scope -> :aveline@handlers@comments.unresolve(ctx, scope, base_id) end)
  end

  # ===== Helpers =====

  defp run(conn, handler) do
    case handler.(CtxBuilder.build(), CtxBuilder.scope(conn)) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  # Body must be a string; anything else fails validation in the
  # handler, same 422 the changeset cast used to produce.
  defp str_opt(value) when is_binary(value), do: {:some, value}
  defp str_opt(_), do: :none

  # Renders a Gleam CommentView into the exact legacy Views.comment map.
  defp render_comment(
         {:comment_view, id, version_id, version_number, doc_id, block_id, parent_comment_id,
          body, actor_type, actor_user, resolved_at, resolved_by, resolved_in_version, edited_at,
          deleted_at, deleted_by, created_at}
       ) do
    %{
      # Stable LOGICAL id — what every other API call references.
      "id" => id,
      # Specific row id of THIS version. Mostly internal.
      "version_id" => version_id,
      "version_number" => version_number,
      "doc_id" => doc_id,
      "block_id" => unopt(block_id),
      "parent_comment_id" => unopt(parent_comment_id),
      "body" => body,
      "actor" => %{
        "type" => actor_type,
        "user" => render_user(actor_user)
      },
      "resolved_at" => unopt(resolved_at),
      "resolved_by" => render_user(resolved_by),
      "resolved_in_version" => unopt(resolved_in_version),
      "edited_at" => unopt(edited_at),
      "deleted_at" => unopt(deleted_at),
      "deleted_by" => render_user(deleted_by),
      "created_at" => created_at
    }
  end

  defp render_user(:none), do: nil

  defp render_user({:some, {:user_ref, id, username, display_name, email}}) do
    %{
      "id" => id,
      "username" => username,
      "display_name" => unopt(display_name),
      "email" => unopt(email)
    }
  end
end
