defmodule AvelineWeb.Api.TagController do
  @moduledoc """
  Tag management endpoints.

  Same `Aveline.Tags.*` context functions the TagsLive uses, so the
  invariants stay shared:

  - Every tag carries a required description (6-280 chars) — the LLM
    needs it to understand what the tag covers when searching.
  - Renaming into a slug that's already taken returns `slug_taken`.
  - Deleting a tag detaches it everywhere; docs may end up tagless
    as its only tag — we keep the "every doc has ≥1 tag" invariant.
  """
  use AvelineWeb, :controller

  alias Aveline.Tags
  alias Aveline.Tags.Tag
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    ws = conn.assigns.current_workspace
    rows = Tags.list_with_stats(ws.id)
    Envelope.ok(conn, %{tags: Enum.map(rows, &Views.tag_with_stats/1)})
  end

  def show(conn, %{"slug" => slug}) do
    ws = conn.assigns.current_workspace

    case Tags.get(ws.id, slug) do
      nil -> {:error, :not_found}
      tag -> Envelope.ok(conn, %{tag: Views.tag(tag)})
    end
  end

  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    # Accept either `slug` or `name` — agents tend to use `name` since
    # that's the friendlier verb on the CLI.
    raw_slug = params["slug"] || params["name"]

    with {:ok, tag} <-
           Tags.create(
             ws.id,
             raw_slug |> to_string() |> String.trim() |> String.downcase(),
             params["description"] |> to_string() |> String.trim(),
             user.id,
             color: params["color"]
           ) do
      Envelope.ok(conn, %{tag: Views.tag(tag)})
    end
  end

  @doc """
  Edit a tag's description and/or slug. Body:
      { "description": "...", "new_slug": "..." }   // both optional

  Renaming the slug cascades through every doc that carries it.
  """
  def update(conn, %{"slug" => slug} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user
    # `name` accepted as an alias for `new_slug` (agent-friendly).
    raw_new = params["new_slug"] || params["name"]

    changes =
      %{}
      |> then(fn c -> if raw_new, do: Map.put(c, :slug, raw_new), else: c end)
      |> then(fn c ->
        case params["description"] do
          nil -> c
          d -> Map.put(c, :description, to_string(d) |> String.trim())
        end
      end)
      |> then(fn c ->
        # "" clears the color back to the default; absent leaves it alone.
        case params["color"] do
          nil -> c
          "" -> Map.put(c, :color, nil)
          color -> Map.put(c, :color, color)
        end
      end)

    with %Tag{} = tag <- Tags.get(ws.id, slug) || {:error, :not_found},
         {:ok, tag} <- Tags.edit(tag, changes, user.id) do
      Envelope.ok(conn, %{tag: Views.tag(tag)})
    else
      {:error, :destination_exists} -> {:error, :slug_taken}
      {:error, _} = err -> err
    end
  end

  @doc """
  Restore a soft-deleted tag. Every doc that carried it shows it again
  instantly — the attachments never left the doc rows.
  """
  def restore(conn, %{"slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %Tag{} = tag <- Tags.get_deleted(ws.id, slug) || {:error, :not_found},
         {:ok, tag} <- Tags.restore(tag, user.id) do
      Envelope.ok(conn, %{tag: Views.tag(tag)})
    end
  end

  def delete(conn, %{"slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %Tag{} = tag <- Tags.get(ws.id, slug) || {:error, :not_found},
         {:ok, _} <- Tags.delete(tag, user.id) do
      Envelope.ok(conn, %{})
    end
  end


end
