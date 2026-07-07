defmodule AvelineWeb.Api.Views do
  @moduledoc """
  Plain-Elixir-map builders for every resource we expose over the API.

  Lives separate from controllers so the same view shape is reused
  between list / show / mutation echoes. Always returns string-keyed
  maps to keep the JSON encoder deterministic.

  Conventions:
  - UUIDs and ids always strings
  - Timestamps are ISO 8601 strings (Jason auto-encodes DateTime, but
    we explicitly stringify so the shape is stable across encoders)
  - User refs are inlined as {id, username, display_name} to save the
    agent a `get-user` roundtrip
  """

  alias Aveline.Comments.Comment
  alias Aveline.Docs.Doc

  # ===== User =====

  def user(nil), do: nil

  def user(%{id: id, username: u} = user) do
    %{
      "id" => id,
      "username" => u,
      "display_name" => Map.get(user, :display_name),
      "email" => Map.get(user, :email)
    }
  end

  # ===== Workspace =====

  def workspace(nil), do: nil

  def workspace(%{id: id, slug: slug, name: name} = ws) do
    %{
      "id" => id,
      "slug" => slug,
      "name" => name,
      "created_at" => iso(Map.get(ws, :inserted_at))
    }
  end

  # ===== Doc =====

  @doc """
  Shape returned by GET /docs (list) — slim, no blocks.
  Agent typically lists to pick a doc, then `get-doc` for full body.
  """
  def doc_summary(%Doc{} = d) do
    %{
      "id" => d.id,
      "base_doc_id" => d.base_doc_id,
      "slug" => d.slug,
      "title" => d.title,
      "summary" => d.summary,
      "tags" => d.tags || [],
      "pin_slot" => d.pin_slot,
      "orientation" => d.orientation,
      "version_number" => d.version_number,
      "owner" => user(preload(d, :owner)),
      "created_at" => iso(Map.get(d, :created_at) || d.inserted_at),
      "updated_at" => iso(d.updated_at)
    }
  end

  @doc """
  Shape returned by GET /docs/:slug — full body, blocks included.
  """
  def doc_full(%Doc{} = d) do
    d
    |> doc_summary()
    |> Map.merge(%{
      "blocks" => d.blocks || [],
      "intent" => d.intent,
      "operations" => d.operations || [],
      "actor" => %{
        "type" => d.actor_type,
        "user" => user(preload(d, :actor_user))
      }
    })
  end

  # ===== Comment =====

  def comment(%Comment{} = c) do
    %{
      # Stable LOGICAL id — what every other API call references.
      "id" => c.base_comment_id,
      # Specific row id of THIS version. Mostly internal.
      "version_id" => c.id,
      "version_number" => c.version_number,
      "doc_id" => c.doc_id,
      "block_id" => c.block_id,
      "parent_comment_id" => c.parent_comment_id,
      "body" => c.body,
      "actor" => %{
        "type" => c.actor_type,
        "user" => user(preload(c, :actor_user))
      },
      "resolved_at" => iso(c.resolved_at),
      "resolved_by" => user(preload(c, :resolved_by)),
      "resolved_in_version" =>
        case preload(c, :resolved_by_doc) do
          nil -> nil
          d -> d.version_number
        end,
      "edited_at" => iso(c.edited_at),
      "deleted_at" => iso(c.deleted_at),
      "deleted_by" => user(preload(c, :deleted_by)),
      "created_at" => iso(c.inserted_at)
    }
  end

  # ===== Tag =====

  def tag(%{slug: slug, description: desc} = t) do
    %{
      "slug" => slug,
      "description" => desc,
      "color" => Map.get(t, :color),
      "sort_key" => Map.get(t, :sort_key),
      "version_number" => Map.get(t, :version_number, 1),
      "created_at" => iso(Map.get(t, :inserted_at))
    }
  end

  def tag_with_stats(%{tag: t, count: count, last_used_at: last}) do
    t
    |> tag()
    |> Map.merge(%{"doc_count" => count, "last_used_at" => iso(last)})
  end

  # ===== Version =====

  def doc_version(%Doc{} = d) do
    %{
      "id" => d.id,
      "version_number" => d.version_number,
      "intent" => d.intent,
      "actor" => %{
        "type" => d.actor_type,
        "user" => user(preload(d, :actor_user))
      },
      "inserted_at" => iso(d.inserted_at)
    }
  end

  # ===== Event =====

  def event(e) do
    %{
      "id" => e.id,
      "action" => e.action,
      "target_kind" => e.target_kind,
      "target_id" => e.target_id,
      "target_slug" => e.target_slug,
      "target_label" => e.target_label,
      "actor" => %{
        "type" => e.actor_type,
        "user" => user(Map.get(e, :actor_user))
      },
      "data" => e.data || %{},
      "occurred_at" => iso(e.inserted_at)
    }
  end

  # ===== Membership =====

  def member(%{user: u, role: role, joined_at: joined}) do
    Map.merge(user(u), %{"role" => role, "joined_at" => iso(joined)})
  end

  def member(%{user: u} = m) do
    Map.merge(user(u), %{
      "role" => Map.get(m, :role, "member"),
      "joined_at" => iso(Map.get(m, :inserted_at) || Map.get(m, :joined_at))
    })
  end

  # ===== Helpers =====

  defp preload(struct, key) do
    case Map.get(struct, key) do
      %Ecto.Association.NotLoaded{} -> nil
      other -> other
    end
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp iso(other), do: other
end
