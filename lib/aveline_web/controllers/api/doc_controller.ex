defmodule AvelineWeb.Api.DocController do
  @moduledoc """
  Doc lifecycle endpoints. Every write path calls the same
  `Aveline.Docs.*` context functions the LiveView calls — controllers
  are thin adapters so business logic doesn't drift between web + API.
  """
  use AvelineWeb, :controller

  alias Aveline.Docs
  alias Aveline.DocViews
  alias Aveline.Kudos
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  # ===== Reads =====

  def index(conn, params) do
    ws = conn.assigns.current_workspace

    items =
      Docs.list_current(ws.id,
        tags: parse_tag_list(params["tag"] || params["tags"])
      )

    Envelope.ok(conn, %{docs: Enum.map(items, &Views.doc_summary/1)})
  end

  def show(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    case Docs.get_current_by_slug(ws.id, slug) do
      nil ->
        {:error, :not_found}

      item ->
        # Record an agent "read" event — same as the LV connects do.
        DocViews.record(ws.id, item.base_doc_id, user.id, "agent")
        item = %{item | blocks: Docs.enrich_doc_links(item.blocks || [], ws.id)}
        Envelope.ok(conn, %{doc: Views.doc_full(item)})
    end
  end

  @doc """
  The workspace orientation doc (well-known slug, seeded at workspace
  creation, undeletable). Agents fetch this first to learn how the
  workspace is laid out. Same shape as GET /docs/:slug.
  """
  def orientation(conn, _params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    case Docs.get_orientation(ws.id) do
      nil ->
        {:error, :not_found}

      item ->
        DocViews.record(ws.id, item.base_doc_id, user.id, "agent")
        item = %{item | blocks: Docs.enrich_doc_links(item.blocks || [], ws.id)}
        Envelope.ok(conn, %{doc: Views.doc_full(item)})
    end
  end

  # ===== Writes =====

  @doc """
  Create a doc. Body:
      {
        "title": "...",
        "slug": "...",                // optional; auto-derived from title
        "summary": "...",              // optional
        "tags": ["..."],               // must exist in workspace
        "blocks": [...],               // block array, see Aveline.Blocks
        "intent": "...",               // why
        "actor": "human" | "agent"     // defaults to "agent" for API
      }

  Success echoes the minimal pointer (slug + ids) the agent needs to
  chain follow-up calls. No body echo — the agent already has the
  blocks it sent.
  """
  def create(conn, params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    attrs = %{
      title: params["title"],
      slug: params["slug"],
      summary: params["summary"],
      tags: params["tags"] || [],
      blocks: params["blocks"] || [],
      workspace_id: ws.id,
      owner_id: user.id,
      actor_user_id: user.id,
      actor_type: params["actor"] || "agent",
      intent: params["intent"]
    }

    with {:ok, item} <- Docs.create_doc(attrs) do
      Envelope.ok(conn, %{
        slug: item.slug,
        doc_id: item.base_doc_id,
        version_id: item.id,
        version_number: item.version_number
      })
    end
  end

  @doc """
  Apply an ops batch to an existing doc (i.e. ship a new version).
  Body:
      {
        "intent": "...",
        "operations": [...],
        "actor": "human" | "agent",
        "comment_dispositions": [
          {"comment_id": "...", "action": "resolve",  "reply": "..."},
          {"comment_id": "...", "action": "reanchor", "new_block_id": "b_xyz"},
          {"comment_id": "...", "action": "leave",    "note": "..."}
        ],
        "title": "...",     // optional metadata overrides
        "summary": "...",
        "tags": [...]
      }

  Returns the new version's id + number so the agent can verify it
  shipped.
  """
  def update(conn, %{"doc_slug" => slug} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = current <- Docs.get_current_by_slug(ws.id, slug) || {:error, :not_found} do
      ops = params["operations"] || []
      intent = params["intent"]
      resolves = params["resolves_comment_ids"] || []
      dispositions = params["comment_dispositions"] || []

      update_attrs =
        %{
          actor_user_id: user.id,
          actor_type: params["actor"] || "agent"
        }
        |> maybe_put(:title, params["title"])
        |> maybe_put(:summary, params["summary"])
        |> maybe_put(:tags, params["tags"])

      with {:ok, item} <-
             Docs.apply_ops(current, ops, update_attrs,
               intent: intent,
               resolves_comment_ids: resolves,
               dispositions: dispositions
             ) do
        Envelope.ok(conn, %{
          slug: item.slug,
          doc_id: item.base_doc_id,
          version_id: item.id,
          version_number: item.version_number
        })
      end
    end
  end

  def delete(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = current <- Docs.get_current_by_slug(ws.id, slug) || {:error, :not_found},
         {:ok, _deleted} <- Docs.soft_delete(current, user.id) do
      Envelope.ok(conn, %{})
    end
  end

  def restore(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace

    case latest_for_slug(ws.id, slug) do
      nil ->
        {:error, :not_found}

      %{base_doc_id: base} ->
        case Docs.restore(base) do
          {:ok, item} ->
            Envelope.ok(conn, %{
              slug: item.slug,
              doc_id: item.base_doc_id,
              version_number: item.version_number
            })

          {:error, :not_user_deleted} ->
            {:error, :not_user_deleted}

          {:error, _} = err ->
            err
        end
    end
  end

  @doc """
  Toggle kudos. Returns the new state (`given_by_me` + `count`) so the
  agent doesn't need a follow-up read.
  """
  def kudos(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    case Docs.get_current_by_slug(ws.id, slug) do
      nil ->
        {:error, :not_found}

      %{owner_id: owner_id} when owner_id == user.id ->
        {:error, :self_kudos, "You can't give kudos to your own doc."}

      item ->
        {:ok, action} = Kudos.toggle(ws.id, item.base_doc_id, user.id)
        count = Kudos.count_for_base(item.base_doc_id)

        Envelope.ok(conn, %{
          given_by_me: action == :given,
          count: count
        })
    end
  end

  @doc """
  Pin a doc to a home-page slot. Body: {"slot": 1..6} — omit slot to
  take the lowest free one. The orientation doc has its own card and
  can't be slotted.
  """
  def pin(conn, %{"doc_slug" => slug} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = current <- Docs.get_current_by_slug(ws.id, slug) || {:error, :not_found},
         {:ok, slot} <- parse_slot(params["slot"]),
         {:ok, doc} <- Docs.pin(current, slot, user.id) do
      Envelope.ok(conn, %{slug: doc.slug, pin_slot: doc.pin_slot})
    end
  end

  def unpin(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with %_{} = current <- Docs.get_current_by_slug(ws.id, slug) || {:error, :not_found},
         {:ok, doc} <- Docs.unpin(current, user.id) do
      Envelope.ok(conn, %{slug: doc.slug, pin_slot: nil})
    end
  end

  defp parse_slot(nil), do: {:ok, nil}
  defp parse_slot(n) when is_integer(n), do: {:ok, n}

  defp parse_slot(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "pin slot must be an integer between 1 and 6"}
    end
  end

  defp parse_slot(_), do: {:error, "pin slot must be an integer between 1 and 6"}

  # ===== Helpers =====

  defp latest_for_slug(ws_id, slug) do
    import Ecto.Query

    Aveline.Repo.one(
      from i in Aveline.Docs.Doc,
        where: i.workspace_id == ^ws_id and i.slug == ^slug,
        order_by: [desc: i.version_number],
        limit: 1
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_tag_list(nil), do: []
  defp parse_tag_list(""), do: []
  defp parse_tag_list(list) when is_list(list), do: Enum.uniq(list)
  defp parse_tag_list(s) when is_binary(s), do: String.split(s, ",", trim: true) |> Enum.uniq()
end
