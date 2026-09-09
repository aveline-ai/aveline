defmodule AvelineWeb.Api.TagController do
  @moduledoc """
  Tag management endpoints — thin adapters over the Gleam handlers in
  src/aveline/handlers/tags.gleam, which own every decision (slug rules,
  versioning, restore semantics). The invariants stay the same:

  - Every tag carries a required description (6-280 chars) — the LLM
    needs it to understand what the tag covers when searching.
  - Renaming into a slug that's already taken returns `slug_taken`.
  - Deleting a tag detaches it everywhere; docs may end up tagless
    as its only tag — we keep the "every doc has ≥1 tag" invariant.
  """
  use AvelineWeb, :controller

  import Aveline.Gleam.Interop

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  def index(conn, _params) do
    rows = :aveline@handlers@tags.index(CtxBuilder.build(), CtxBuilder.scope(conn))
    Envelope.ok(conn, %{tags: Enum.map(rows, &tag_stats_json/1)})
  end

  def show(conn, %{"slug" => slug}) do
    case :aveline@handlers@tags.show(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, tag} -> Envelope.ok(conn, %{tag: tag_json(tag)})
      {:error, err} -> tag_error(err)
    end
  end

  def create(conn, params) do
    # Accept either `slug` or `name` — agents tend to use `name` since
    # that's the friendlier verb on the CLI.
    raw_slug = params["slug"] || params["name"]

    request =
      {:create_request, to_string(raw_slug), to_string(params["description"]),
       blankable_opt(params["color"]), blankable_opt(params["sort_key"])}

    case :aveline@handlers@tags.create(CtxBuilder.build(), CtxBuilder.scope(conn), request) do
      {:ok, tag} -> Envelope.ok(conn, %{tag: tag_json(tag)})
      {:error, err} -> tag_error(err)
    end
  end

  @doc """
  Edit a tag's description and/or slug. Body:
      { "description": "...", "new_slug": "..." }   // both optional

  Renaming the slug cascades through every doc that carries it.
  `""` clears color / sort_key back to the default; absent leaves them.
  """
  def update(conn, %{"slug" => slug} = params) do
    # `name` accepted as an alias for `new_slug` (agent-friendly).
    raw_new = params["new_slug"] || params["name"]

    request =
      {:update_request, opt(raw_new, &to_string/1),
       opt(params["description"], fn d -> d |> to_string() |> String.trim() end),
       patch(params["color"]), patch(params["sort_key"])}

    case :aveline@handlers@tags.update(CtxBuilder.build(), CtxBuilder.scope(conn), slug, request) do
      {:ok, tag} -> Envelope.ok(conn, %{tag: tag_json(tag)})
      {:error, err} -> tag_error(err)
    end
  end

  @doc """
  Restore a soft-deleted tag. Every doc that carried it shows it again
  instantly — the attachments never left the doc rows.
  """
  def restore(conn, %{"slug" => slug}) do
    case :aveline@handlers@tags.restore(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, tag} -> Envelope.ok(conn, %{tag: tag_json(tag)})
      {:error, err} -> tag_error(err)
    end
  end

  def delete(conn, %{"slug" => slug}) do
    case :aveline@handlers@tags.delete(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> tag_error(err)
    end
  end

  # ===== Boundary helpers =====

  # slug_taken keeps its legacy fallback tuple so the envelope keeps its
  # `field: "slug"` detail; everything else goes through the adapter.
  defp tag_error({:invalid, "slug_taken", _msg}), do: {:error, :slug_taken}
  defp tag_error(err), do: GleamAdapter.error(err)

  # Create-time optional string: absent or "" mean "no value" (an empty
  # string cast to nil in the legacy changeset path).
  defp blankable_opt(nil), do: :none
  defp blankable_opt(""), do: :none
  defp blankable_opt(value), do: {:some, to_string(value)}

  # Update-time patch semantics: absent = keep, "" = clear, value = set.
  defp patch(nil), do: :keep
  defp patch(""), do: :clear
  defp patch(value), do: {:set, to_string(value)}

  defp tag_json({:tag, _id, _base, version_number, slug, description, color, sort_key, _sup, created_at}) do
    %{
      "slug" => slug,
      "description" => description,
      "color" => unopt(color),
      "sort_key" => unopt(sort_key),
      "version_number" => version_number,
      "created_at" => created_at
    }
  end

  defp tag_stats_json({:tag_stats, tag, doc_count, last_used_at}) do
    tag
    |> tag_json()
    |> Map.merge(%{"doc_count" => doc_count, "last_used_at" => unopt(last_used_at)})
  end
end
