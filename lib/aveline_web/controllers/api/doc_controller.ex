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
  alias Aveline.Workspaces
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.Views

  action_fallback AvelineWeb.Api.FallbackController

  # ===== Reads =====

  # Results are capped so an unbounded corpus can't blow out an agent's
  # context window; explicit ?limit goes up to @max_limit.
  @default_limit 25
  @max_limit 100

  def index(conn, params) do
    ws = conn.assigns.current_workspace

    with {:ok, sort} <- parse_sort(params["sort"]),
         {:ok, limit} <- parse_limit(params["limit"]),
         {:ok, offset} <- parse_offset(params["offset"]),
         {:ok, owner_ids} <- resolve_authors(ws.id, parse_tag_list(params["author"] || params["authors"])) do
      items =
        Docs.list_current(ws.id,
          viewer: conn.assigns.current_user.id,
          tags: parse_tag_list(params["tag"] || params["tags"]),
          updated: params["edited"] || params["updated"],
          search: params["q"],
          sort: sort,
          owner_ids: owner_ids,
          limit: limit,
          offset: offset
        )

      Envelope.ok(conn, %{docs: Enum.map(items, &Views.doc_summary/1)})
    end
  end

  # nil sort → Docs.list_current picks (relevance with a query, recency without).
  defp parse_sort(nil), do: {:ok, nil}
  defp parse_sort(""), do: {:ok, nil}
  defp parse_sort("recent"), do: {:ok, :recent}
  defp parse_sort("kudos"), do: {:ok, :kudos}
  defp parse_sort("views"), do: {:ok, :views}
  defp parse_sort("relevance"), do: {:ok, :relevance}

  defp parse_sort(other),
    do: {:error, {:list_param_invalid, "sort must be recent | kudos | views | relevance, got: #{inspect(other)}"}}

  defp parse_limit(nil), do: {:ok, @default_limit}
  defp parse_limit(""), do: {:ok, @default_limit}

  defp parse_limit(raw) do
    case Integer.parse(to_string(raw)) do
      {n, ""} when n in 1..@max_limit ->
        {:ok, n}

      _ ->
        {:error, {:list_param_invalid, "limit must be an integer between 1 and #{@max_limit}"}}
    end
  end

  defp parse_offset(nil), do: {:ok, 0}
  defp parse_offset(""), do: {:ok, 0}

  defp parse_offset(raw) do
    case Integer.parse(to_string(raw)) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, {:list_param_invalid, "offset must be a non-negative integer"}}
    end
  end

  defp resolve_authors(_ws_id, []), do: {:ok, []}

  defp resolve_authors(ws_id, usernames) do
    by_name =
      ws_id
      |> Workspaces.list_members()
      |> Map.new(fn m -> {m.user.username, m.user.id} end)

    case Enum.reject(usernames, &Map.has_key?(by_name, &1)) do
      [] -> {:ok, Enum.map(usernames, &Map.fetch!(by_name, &1))}
      unknown -> {:error, {:unknown_authors, unknown}}
    end
  end

  def show(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    case fetch_readable(ws, user, slug) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, item} ->
        # Record an agent "read" event — same as the LV connects do.
        DocViews.record(ws.id, item.base_doc_id, user.id, "agent")
        # Reads return chart CONFIG, not data — a doc read never dials a
        # customer database. Agents fetch rows explicitly via run-block.
        item = %{item | blocks: Docs.enrich_blocks(item.blocks || [], ws.id, run_charts: false, viewer: user.id)}
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
        item = %{item | blocks: Docs.enrich_blocks(item.blocks || [], ws.id, run_charts: false, viewer: user.id)}
        Envelope.ok(conn, %{doc: Views.doc_full(item)})
    end
  end

  @doc """
  Run one chart block and return its rows — the explicit path to chart
  data now that reads return config only. Same result shape as
  query-data-source: returned, never stored.
  """
  def run_block(conn, %{"doc_slug" => slug, "block_id" => block_id}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, item} <- fetch_readable(ws, user, slug),
         %{"type" => "chart"} = block <- find_chart(item.blocks, block_id) || {:error, :not_found} do
      case Docs.run_chart(ws.id, block) do
        %{"error" => msg} -> {:error, :query_failed, msg}
        result -> Envelope.ok(conn, result)
      end
    end
  end

  defp find_chart(blocks, block_id) do
    Enum.find(blocks || [], &(&1["type"] == "chart" and &1["id"] == block_id))
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
      intent: params["intent"],
      # Low-spam default: docs are born private; publishing to the
      # workspace is an explicit act (agents pass whatever gets the
      # thing done, so the zero-effort path must be the quiet one).
      visibility: params["visibility"] || "private"
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
  Ship a new version of an existing doc. Two input modes (send one, not
  both):

    * `blocks` — the whole document as it should end up. The server
      reconciles against the current blocks by stable id (matching id =
      same block, content updated; id-less/unknown = new; missing =
      deleted) and ships the result. The easy path: get-doc, change what
      you want, send it all back. Symmetric with create-doc.
    * `operations` — a surgical ops array (append_block, insert_block,
      modify_block, delete_block, move_block) for touching one block in a
      large doc without resending it.

  Full body:
      {
        "blocks": [...]        // OR
        "operations": [...],
        "intent": "...",
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

  Editing a block that carries an open comment requires a disposition for
  that thread, in either mode. Returns the new version's id + number so
  the agent can verify it shipped.
  """
  def update(conn, %{"doc_slug" => slug} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user
    blocks = params["blocks"]
    ops = params["operations"]

    with {:ok, current} <- fetch_readable(ws, user, slug),
         :ok <- ensure_editable(current, user),
         :ok <- validate_edit_mode(blocks, ops) do
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

      result =
        if is_list(blocks) do
          Docs.replace_blocks(current, blocks, update_attrs,
            intent: intent,
            resolves_comment_ids: resolves,
            dispositions: dispositions
          )
        else
          Docs.apply_ops(current, ops || [], update_attrs,
            intent: intent,
            resolves_comment_ids: resolves,
            dispositions: dispositions
          )
        end

      with {:ok, item} <- result do
        Envelope.ok(conn, %{
          slug: item.slug,
          doc_id: item.base_doc_id,
          version_id: item.id,
          version_number: item.version_number
        })
      end
    end
  end

  # Exactly one of blocks / operations. Both is ambiguous (which wins?);
  # neither is a no-op edit — reject both so the agent gets a clear error
  # instead of a silent surprise.
  defp validate_edit_mode(blocks, ops) when is_list(blocks) and is_list(ops),
    do: {:error, :bad_request, "send either blocks (full replace) or operations (surgical), not both"}

  defp validate_edit_mode(_, _), do: :ok

  def delete(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, current} <- fetch_readable(ws, user, slug),
         :ok <- ensure_editable(current, user),
         {:ok, _deleted} <- Docs.soft_delete(current, user.id) do
      Envelope.ok(conn, %{})
    end
  end

  def restore(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    case latest_for_slug(ws.id, slug) do
      nil ->
        {:error, :not_found}

      # A deleted private doc stays private: only its owner can restore
      # it, and to anyone else it does not exist.
      %{visibility: "private", owner_id: owner_id} when owner_id != user.id ->
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

    case fetch_readable(ws, user, slug) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, %{owner_id: owner_id}} when owner_id == user.id ->
        {:error, :self_kudos, "You can't give kudos to your own doc."}

      {:ok, item} ->
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

    with {:ok, current} <- fetch_readable(ws, user, slug),
         {:ok, slot} <- parse_slot(params["slot"]),
         {:ok, doc} <- Docs.pin(current, slot, user.id) do
      Envelope.ok(conn, %{slug: doc.slug, pin_slot: doc.pin_slot})
    end
  end

  def unpin(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, current} <- fetch_readable(ws, user, slug),
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

  # ===== Visibility & shares =====

  @doc """
  Change a doc's visibility in place: "private" | "workspace". Owner
  only. Does not create a version — visibility is placement-style
  state, like pin slots.
  """
  def set_visibility(conn, %{"doc_slug" => slug, "visibility" => vis}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, current} <- fetch_readable(ws, user, slug),
         {:ok, item} <- Docs.set_visibility(current, vis, user.id) do
      Envelope.ok(conn, %{slug: item.slug, doc_id: item.base_doc_id, visibility: item.visibility})
    end
  end

  def set_visibility(_conn, _params), do: {:error, {:missing_field, "visibility"}}

  @doc """
  Grant a workspace member access to a private doc. Body:
  {"username": "...", "role": "viewer" | "editor"} (role defaults to
  viewer). Owner only; upserts the live share.
  """
  def share(conn, %{"doc_slug" => slug, "username" => username} = params) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, current} <- fetch_readable(ws, user, slug),
         %_{} = target <- Aveline.Accounts.get_user_by_username(username) || {:error, :not_member},
         {:ok, share} <- Docs.share_doc(current, target.id, params["role"] || "viewer", user.id) do
      Envelope.ok(conn, %{
        slug: current.slug,
        doc_id: current.base_doc_id,
        username: username,
        role: share.role
      })
    end
  end

  def share(_conn, _params), do: {:error, {:missing_field, "username"}}

  @doc "Revoke a member's share. Owner only."
  def unshare(conn, %{"doc_slug" => slug, "username" => username}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, current} <- fetch_readable(ws, user, slug),
         %_{} = target <- Aveline.Accounts.get_user_by_username(username) || {:error, :not_member},
         {:ok, _share} <- Docs.unshare_doc(current, target.id, user.id) do
      Envelope.ok(conn, %{slug: current.slug, doc_id: current.base_doc_id, username: username})
    end
  end

  def unshare(_conn, _params), do: {:error, {:missing_field, "username"}}

  @doc "Live shares on a doc, with usernames. Readable by anyone who can read the doc."
  def shares(conn, %{"doc_slug" => slug}) do
    ws = conn.assigns.current_workspace
    user = conn.assigns.current_user

    with {:ok, current} <- fetch_readable(ws, user, slug) do
      shares =
        Enum.map(Docs.list_shares(current), fn s ->
          %{
            username: s.user && s.user.username,
            role: s.role,
            granted_by: s.granted_by && s.granted_by.username,
            granted_at: s.inserted_at
          }
        end)

      Envelope.ok(conn, %{
        slug: current.slug,
        doc_id: current.base_doc_id,
        visibility: current.visibility,
        shares: shares
      })
    end
  end

  # ===== Helpers =====

  # One access rule for every by-slug endpoint. Inaccessible and
  # nonexistent are indistinguishable on purpose: existence is
  # information.
  defp fetch_readable(ws, user, slug) do
    case Docs.get_current_by_slug(ws.id, slug) do
      nil -> {:error, :not_found}
      item -> if Docs.member_can_read?(item, user.id), do: {:ok, item}, else: {:error, :not_found}
    end
  end

  defp ensure_editable(item, user) do
    if Docs.member_can_edit?(item, user.id),
      do: :ok,
      else: {:error, :forbidden, "You have viewer access to this doc; editing needs an editor share or ownership."}
  end

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
