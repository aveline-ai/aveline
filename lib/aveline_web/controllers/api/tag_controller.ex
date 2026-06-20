defmodule AvelineWeb.Api.TagController do
  @moduledoc """
  Tag management endpoints.

  Same `Aveline.Tags.*` context functions the TagsLive uses, so the
  invariants stay shared:

  - Every tag carries a required description (6-280 chars) — the LLM
    needs it to understand what the tag covers when searching.
  - Renaming into a slug that's already taken returns `slug_taken`.
  - Deleting a tag returns `would_orphan_docs` if any doc uses it
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
             user.id
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
    new_slug = (raw_new || slug) |> to_string() |> String.trim() |> String.downcase()
    # Distinguish "no description in payload" (skip) from "" (caller is
    # trying to clear it — that's a validation error).
    desc_param = params["description"]

    with %Tag{} = tag <- Tags.get(ws.id, slug) || {:error, :not_found},
         {:ok, tag} <- maybe_rename(tag, new_slug, user.id),
         {:ok, tag} <- maybe_update_desc(tag, desc_param, user.id) do
      Envelope.ok(conn, %{tag: Views.tag(tag)})
    else
      {:error, :destination_exists} -> {:error, :slug_taken}
      {:error, _} = err -> err
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

  defp maybe_rename(%Tag{slug: same} = tag, same, _user_id), do: {:ok, tag}
  defp maybe_rename(tag, new_slug, user_id), do: Tags.rename(tag, new_slug, user_id)

  # nil ⇒ caller didn't pass --description, leave as-is.
  defp maybe_update_desc(tag, nil, _user_id), do: {:ok, tag}
  defp maybe_update_desc(%Tag{description: same} = tag, same, _user_id), do: {:ok, tag}
  defp maybe_update_desc(_tag, "", _user_id),
    do: {:error, %Ecto.Changeset{errors: [description: {"can't be blank", []}]}}
  defp maybe_update_desc(tag, desc, user_id) when is_binary(desc) do
    Tags.update_description(tag, String.trim(desc), user_id)
  end
end
