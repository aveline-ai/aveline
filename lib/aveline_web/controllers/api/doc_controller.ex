defmodule AvelineWeb.Api.DocController do
  @moduledoc """
  Doc lifecycle endpoints. Thin adapters: raw params are marshalled into
  typed Gleam requests, the handlers under src/aveline/handlers/ make
  every decision (with IO injected as Ctx caps), and results render back
  through Envelope / GleamAdapter so codes and envelopes are unchanged.
  """
  use AvelineWeb, :controller

  import Aveline.Gleam.Interop

  alias Aveline.Gleam.CtxBuilder
  alias AvelineWeb.Api.Envelope
  alias AvelineWeb.Api.GleamAdapter

  action_fallback AvelineWeb.Api.FallbackController

  # ===== Reads =====

  def index(conn, params) do
    req =
      {:list_request, sort_param(params["sort"]), int_ish(params["limit"]),
       int_ish(params["offset"]), raw_list(params["tag"] || params["tags"]),
       raw_list(params["author"] || params["authors"]), opt(params["edited"]),
       opt(params["updated"]), opt(params["q"])}

    case :aveline@handlers@doc_list.index(CtxBuilder.build(), CtxBuilder.scope(conn), req) do
      {:ok, docs} -> Envelope.ok(conn, %{docs: docs})
      {:error, err} -> GleamAdapter.doc_error(err)
    end
  end

  def show(conn, %{"doc_slug" => slug}) do
    case :aveline@handlers@doc_read.show(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, doc} -> Envelope.ok(conn, %{doc: doc})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  @doc """
  The workspace orientation doc (well-known slug, seeded at workspace
  creation, undeletable). Agents fetch this first to learn how the
  workspace is laid out. Same shape as GET /docs/:slug.
  """
  def orientation(conn, _params) do
    case :aveline@handlers@doc_read.orientation(CtxBuilder.build(), CtxBuilder.scope(conn)) do
      {:ok, doc} -> Envelope.ok(conn, %{doc: doc})
      {:error, err} -> GleamAdapter.error(err)
    end
  end

  @doc """
  Run one chart block and return its rows — the explicit path to chart
  data now that reads return config only. Same result shape as
  query-data-source: returned, never stored.
  """
  def run_block(conn, %{"doc_slug" => slug, "block_id" => block_id}) do
    case :aveline@handlers@doc_read.run_block(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           slug,
           block_id
         ) do
      {:ok, result} -> Envelope.ok(conn, result)
      {:error, err} -> GleamAdapter.error(err)
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
    req =
      {:create_request, opt(params["title"]), opt(params["slug"]), opt(params["summary"]),
       params["tags"] || [], params["blocks"] || [], opt(params["intent"]),
       falsy_opt(params["actor"]), falsy_opt(params["visibility"])}

    case :aveline@handlers@doc_write.create(CtxBuilder.build(), CtxBuilder.scope(conn), req) do
      {:ok, pointer} -> render_pointer(conn, pointer)
      {:error, err} -> GleamAdapter.doc_error(err)
    end
  end

  @doc """
  Ship a new version of an existing doc. Two input modes (send one, not
  both):

    * `blocks` — the whole document as it should end up (full replace,
      reconciled by stable block id).
    * `operations` — a surgical ops array for touching one block in a
      large doc without resending it.

  Editing a block that carries an open comment requires a disposition for
  that thread, in either mode. Returns the new version's id + number so
  the agent can verify it shipped.
  """
  def update(conn, %{"doc_slug" => slug} = params) do
    blocks = params["blocks"]
    ops = params["operations"]

    req =
      {:update_request, if(is_list(blocks), do: {:some, blocks}, else: :none), is_list(ops),
       ops || [], opt(params["title"]), opt(params["summary"]), opt(params["tags"]),
       opt(params["intent"]), falsy_opt(params["actor"]), params["resolves_comment_ids"] || [],
       params["comment_dispositions"] || []}

    case :aveline@handlers@doc_write.update(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           slug,
           req
         ) do
      {:ok, pointer} -> render_pointer(conn, pointer)
      {:error, err} -> GleamAdapter.doc_error(err)
    end
  end

  def delete(conn, %{"doc_slug" => slug}) do
    case :aveline@handlers@doc_write.delete(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, nil} -> Envelope.ok(conn, %{})
      {:error, err} -> GleamAdapter.doc_error(err)
    end
  end

  def restore(conn, %{"doc_slug" => slug}) do
    case :aveline@handlers@doc_write.restore(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, {:restored_doc, slug, doc_id, version_number}} ->
        Envelope.ok(conn, %{slug: slug, doc_id: doc_id, version_number: version_number})

      {:error, err} ->
        GleamAdapter.doc_error(err)
    end
  end

  @doc """
  Toggle kudos. Returns the new state (`given_by_me` + `count`) so the
  agent doesn't need a follow-up read.
  """
  def kudos(conn, %{"doc_slug" => slug}) do
    case :aveline@handlers@doc_kudos.toggle(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, {:kudos_response, given_by_me, count}} ->
        Envelope.ok(conn, %{given_by_me: given_by_me, count: count})

      {:error, err} ->
        GleamAdapter.error(err)
    end
  end

  @doc """
  Pin a doc to a home-page slot. Body: {"slot": 1..6} — omit slot to
  take the lowest free one. The orientation doc has its own card and
  can't be slotted.
  """
  def pin(conn, %{"doc_slug" => slug} = params) do
    case :aveline@handlers@doc_pins.pin(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           slug,
           slot_param(params["slot"])
         ) do
      {:ok, {:pin_response, slug, pin_slot}} ->
        Envelope.ok(conn, %{slug: slug, pin_slot: unopt(pin_slot)})

      {:error, err} ->
        GleamAdapter.doc_error(err)
    end
  end

  def unpin(conn, %{"doc_slug" => slug}) do
    case :aveline@handlers@doc_pins.unpin(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, {:pin_response, slug, pin_slot}} ->
        Envelope.ok(conn, %{slug: slug, pin_slot: unopt(pin_slot)})

      {:error, err} ->
        GleamAdapter.doc_error(err)
    end
  end

  # ===== Visibility & shares =====

  @doc """
  Change a doc's visibility in place: "private" | "workspace". Owner
  only. Does not create a version — visibility is placement-style
  state, like pin slots.
  """
  def set_visibility(conn, %{"doc_slug" => slug, "visibility" => vis}) do
    case :aveline@handlers@doc_sharing.set_visibility(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           slug,
           vis
         ) do
      {:ok, {:visibility_response, slug, doc_id, visibility}} ->
        Envelope.ok(conn, %{slug: slug, doc_id: doc_id, visibility: visibility})

      {:error, err} ->
        GleamAdapter.doc_error(err)
    end
  end

  def set_visibility(_conn, _params), do: {:error, {:missing_field, "visibility"}}

  @doc """
  Grant a workspace member access to a private doc. Body:
  {"username": "...", "role": "viewer" | "editor"} (role defaults to
  viewer). Owner only; upserts the live share.
  """
  def share(conn, %{"doc_slug" => slug, "username" => username} = params) do
    case :aveline@handlers@doc_sharing.share(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           slug,
           username,
           falsy_opt(params["role"])
         ) do
      {:ok, {:share_response, slug, doc_id, username, role}} ->
        Envelope.ok(conn, %{slug: slug, doc_id: doc_id, username: username, role: role})

      {:error, err} ->
        GleamAdapter.doc_error(err)
    end
  end

  def share(_conn, _params), do: {:error, {:missing_field, "username"}}

  @doc "Revoke a member's share. Owner only."
  def unshare(conn, %{"doc_slug" => slug, "username" => username}) do
    case :aveline@handlers@doc_sharing.unshare(
           CtxBuilder.build(),
           CtxBuilder.scope(conn),
           slug,
           username
         ) do
      {:ok, {:unshare_response, slug, doc_id, username}} ->
        Envelope.ok(conn, %{slug: slug, doc_id: doc_id, username: username})

      {:error, err} ->
        GleamAdapter.doc_error(err)
    end
  end

  def unshare(_conn, _params), do: {:error, {:missing_field, "username"}}

  @doc "Live shares on a doc, with usernames. Readable by anyone who can read the doc."
  def shares(conn, %{"doc_slug" => slug}) do
    case :aveline@handlers@doc_sharing.shares(CtxBuilder.build(), CtxBuilder.scope(conn), slug) do
      {:ok, {:shares_response, slug, doc_id, visibility, shares}} ->
        Envelope.ok(conn, %{
          slug: slug,
          doc_id: doc_id,
          visibility: visibility,
          shares: Enum.map(shares, &share_info/1)
        })

      {:error, err} ->
        GleamAdapter.error(err)
    end
  end

  # ===== Marshalling helpers =====

  defp render_pointer(conn, {:doc_pointer, slug, doc_id, version_id, version_number}) do
    Envelope.ok(conn, %{
      slug: slug,
      doc_id: doc_id,
      version_id: version_id,
      version_number: version_number
    })
  end

  defp share_info({:share_info, username, role, granted_by, granted_at}) do
    %{username: unopt(username), role: role, granted_by: unopt(granted_by), granted_at: granted_at}
  end

  # `||`-style default params: false collapses like the legacy code.
  defp falsy_opt(value) when value in [nil, false], do: :none
  defp falsy_opt(value), do: {:some, value}

  defp sort_param(nil), do: :none
  defp sort_param(sort) when is_binary(sort), do: {:some, sort}
  defp sort_param(other), do: {:some, inspect(other)}

  defp int_ish(nil), do: :none
  defp int_ish(value), do: {:some, to_string(value)}

  # A param that may arrive absent, comma-separated, or repeated.
  defp raw_list(nil), do: :no_value
  defp raw_list(values) when is_list(values), do: {:many_values, values}
  defp raw_list(value) when is_binary(value), do: {:one_value, value}

  defp slot_param(nil), do: :no_slot
  defp slot_param(slot) when is_integer(slot), do: {:int_slot, slot}
  defp slot_param(slot) when is_binary(slot), do: {:raw_slot, slot}
  defp slot_param(_), do: :bad_slot
end
