defmodule Aveline.Comments.Disposition do
  @moduledoc """
  When an agent submits a new doc version, every **open** comment thread
  anchored to a block that this op set *touches* (delete or modify) MUST
  be dispositioned. Doc-level threads and threads on untouched blocks are
  optional — the agent may resolve them opportunistically but isn't
  forced to. The goal is the lever over Notion: edits cannot silently
  leave stale comments hanging off blocks they changed.

  Three actions:

    * `"resolve"`  — the new version addresses the comment. The agent
      MUST include a non-empty `reply` body; the server posts it as a
      child comment under the resolved thread (authored by the agent,
      anchored on the same block as the parent) and *then* marks the
      parent resolved. Result reads in the UI as a normal thread reply
      with a "resolved in v3" tag.
    * `"reanchor"` — the comment is still open, but the block it pointed
      at has changed shape (split, merged, renamed). The agent picks a
      new `new_block_id` in the new version's blocks. Optional `note`.
    * `"leave"`    — open, no anchor change. The agent acknowledges the
      thread but isn't addressing it in this edit. Illegal on a comment
      whose block was deleted (the anchor is gone).

  An entry looks like:

      %{
        "comment_id" => "uuid",
        "action" => "resolve" | "reanchor" | "leave",
        "reply" => "...",            # required iff action == "resolve"
        "new_block_id" => "b_xyz",   # required iff action == "reanchor"
        "note" => "..."              # optional metadata for reanchor/leave
      }
  """

  alias Aveline.Comments.Comment

  @actions ~w(resolve reanchor leave)

  defstruct [:comment_id, :action, :new_block_id, :reply, :note]

  @type t :: %__MODULE__{
          comment_id: binary,
          action: String.t(),
          new_block_id: String.t() | nil,
          reply: String.t() | nil,
          note: String.t() | nil
        }

  def actions, do: @actions

  @doc """
  Normalize a single raw disposition map into a `%Disposition{}`. Per-action
  shape rules (resolve → reply required, reanchor → new_block_id required)
  are enforced here so the validator below only worries about coverage and
  deleted-block constraints.
  """
  def cast(%{} = raw) do
    with {:ok, id}     <- fetch_string(raw, "comment_id"),
         {:ok, action} <- fetch_action(raw),
         {:ok, anchor} <- fetch_anchor(action, raw),
         {:ok, reply}  <- fetch_reply(action, raw) do
      {:ok,
       %__MODULE__{
         comment_id: id,
         action: action,
         new_block_id: anchor,
         reply: reply,
         note: raw["note"] |> to_string_or_nil()
       }}
    end
  end

  def cast(_), do: {:error, :invalid_disposition}

  @doc """
  Validate a list of dispositions against the *required* open comment ids
  (those anchored to a touched block in this op set), the comments whose
  block was deleted (where `leave` is illegal), and the new version's
  block ids (for reanchor target checking).

  Extra dispositions (covering optional comments) are allowed and pass
  through; their per-action shape was already enforced by `cast/1`. The
  reanchor target check applies to *all* dispositions, required or not.
  """
  def validate(dispositions, required_ids, deleted_anchor_ids, new_block_ids)
      when is_list(dispositions) and is_list(required_ids) and
             is_list(deleted_anchor_ids) and is_list(new_block_ids) do
    dispo_ids = Enum.map(dispositions, & &1.comment_id)
    required_set = MapSet.new(required_ids)
    dispo_set = MapSet.new(dispo_ids)
    deleted_set = MapSet.new(deleted_anchor_ids)

    cond do
      length(dispo_ids) != MapSet.size(dispo_set) ->
        {:error, {:duplicate_dispositions, dispo_ids -- Enum.uniq(dispo_ids)}}

      not MapSet.subset?(required_set, dispo_set) ->
        missing = MapSet.difference(required_set, dispo_set) |> MapSet.to_list()
        {:error, {:disposition_missing, missing}}

      true ->
        with :ok <- validate_deleted_block_actions(dispositions, deleted_set) do
          validate_reanchors(dispositions, MapSet.new(new_block_ids))
        end
    end
  end

  defp validate_deleted_block_actions([], _deleted), do: :ok

  defp validate_deleted_block_actions(
         [%__MODULE__{action: "leave", comment_id: id} | rest],
         deleted
       ) do
    if MapSet.member?(deleted, id),
      do: {:error, {:leave_on_deleted_block, id}},
      else: validate_deleted_block_actions(rest, deleted)
  end

  defp validate_deleted_block_actions([_ | rest], deleted),
    do: validate_deleted_block_actions(rest, deleted)

  defp validate_reanchors([], _block_set), do: :ok

  defp validate_reanchors([%__MODULE__{action: "reanchor", new_block_id: id} = d | rest], blocks) do
    if MapSet.member?(blocks, id),
      do: validate_reanchors(rest, blocks),
      else: {:error, {:reanchor_target_missing, d.comment_id, id}}
  end

  defp validate_reanchors([_ | rest], blocks), do: validate_reanchors(rest, blocks)

  @doc """
  Apply a dispositions list inside an Ecto.Multi step. `resolve` posts a
  child reply comment on the resolved thread (authored by `agent_user_id`
  on the just-inserted doc version `new_doc_id`, inheriting the parent's
  block anchor) before marking the parent resolved. `reanchor` rewrites
  the parent's block_id. `leave` is a no-op.
  """
  def apply(repo, dispositions, now, agent_user_id, new_doc_id)
      when is_list(dispositions) do
    Enum.reduce_while(dispositions, {:ok, 0}, fn d, {:ok, n} ->
      case do_apply(repo, d, now, agent_user_id, new_doc_id) do
        {:ok, _} -> {:cont, {:ok, n + 1}}
        :ok      -> {:cont, {:ok, n + 1}}
        {:error, e} -> {:halt, {:error, e}}
      end
    end)
  end

  defp do_apply(
         repo,
         %__MODULE__{action: "resolve", comment_id: base_id, reply: reply},
         now,
         uid,
         doc_id
       ) do
    case fetch_current(repo, base_id) do
      nil ->
        {:error, {:comment_not_found, base_id}}

      %Comment{} = parent ->
        # Post the agent's reply first so the thread reads chronologically
        # (original → reply → resolved). Inherit the parent's block anchor
        # so the reply lives on the same block in the UI. New base id is
        # minted up front so the inserted row carries `base_comment_id == id`.
        reply_id = Ecto.UUID.generate()

        reply_attrs = %{
          "base_comment_id" => reply_id,
          "version_number" => 1,
          "doc_id" => doc_id,
          "parent_comment_id" => parent.base_comment_id,
          "block_id" => parent.block_id,
          "body" => reply,
          "actor_user_id" => uid,
          "actor_type" => "agent"
        }

        with {:ok, _reply} <-
               repo.insert(Comment.create_changeset(%Comment{id: reply_id}, reply_attrs)) do
          parent
          |> Ecto.Changeset.change(%{
            resolved_at: now,
            resolved_by_id: uid,
            resolved_by_doc_id: doc_id
          })
          |> repo.update()
        end
    end
  end

  defp do_apply(
         repo,
         %__MODULE__{action: "reanchor", comment_id: base_id, new_block_id: bid},
         _now,
         _uid,
         _doc_id
       ) do
    # Reanchor = mutate `block_id` on the comment's live row. We rely on
    # the auto-forward step (run earlier in the same transaction by
    # Docs.apply_ops) to have already inserted a new comment-version row
    # pinned to the new doc-version. So "fetch_current by base" returns
    # that just-forwarded row; updating its block_id in-place gives us
    # the per-doc-version anchor change without a redundant extra row.
    case fetch_current(repo, base_id) do
      nil -> {:error, {:comment_not_found, base_id}}
      c -> c |> Ecto.Changeset.change(%{block_id: bid}) |> repo.update()
    end
  end

  defp do_apply(_repo, %__MODULE__{action: "leave"}, _now, _uid, _doc_id), do: :ok

  # Dispositions reference comments by their LOGICAL (base) id — the
  # current version is whichever row matches that base with deleted_at
  # IS NULL.
  defp fetch_current(repo, base_id) do
    import Ecto.Query

    repo.one(
      from c in Comment,
        where:
          c.base_comment_id == ^base_id and not c.superseded and
            is_nil(c.deleted_at)
    )
  end

  @doc "Strip a list of structs back to plain maps for JSON storage on the Doc row."
  def to_json(dispositions) when is_list(dispositions) do
    Enum.map(dispositions, fn d ->
      %{
        "comment_id" => d.comment_id,
        "action" => d.action,
        "new_block_id" => d.new_block_id,
        "reply" => d.reply,
        "note" => d.note
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()
    end)
  end

  # ===== helpers =====

  defp fetch_string(map, key) do
    case map[key] do
      s when is_binary(s) and s != "" -> {:ok, s}
      _ -> {:error, {:missing_field, key}}
    end
  end

  defp fetch_action(map) do
    case map["action"] do
      a when a in @actions -> {:ok, a}
      other -> {:error, {:invalid_action, other}}
    end
  end

  defp fetch_anchor("reanchor", map) do
    case map["new_block_id"] do
      s when is_binary(s) and s != "" -> {:ok, s}
      _ -> {:error, {:missing_field, "new_block_id"}}
    end
  end

  defp fetch_anchor(_action, _map), do: {:ok, nil}

  defp fetch_reply("resolve", map) do
    case map["reply"] do
      s when is_binary(s) ->
        case String.trim(s) do
          "" -> {:error, {:missing_field, "reply"}}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, {:missing_field, "reply"}}
    end
  end

  defp fetch_reply(_action, _map), do: {:ok, nil}

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(""), do: nil
  defp to_string_or_nil(s) when is_binary(s), do: s
  defp to_string_or_nil(_), do: nil
end
