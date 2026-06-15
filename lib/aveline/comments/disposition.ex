defmodule Aveline.Comments.Disposition do
  @moduledoc """
  When an agent submits a new doc version, every currently-open top-level
  comment thread on that base doc MUST be dispositioned. A disposition is
  the agent's explicit decision about what this edit means for each thread.

  Three actions:

    * `"resolve"`  — the new version addresses the comment. The thread is
      closed and tagged as resolved-by-version (not by a human click).
    * `"reanchor"` — the comment is still open, but the block it pointed
      at has changed shape (split, merged, renamed). The agent picks a new
      `new_block_id` in the new version's blocks to point the thread at.
    * `"leave"`    — open, no anchor change. The agent acknowledges the
      thread but isn't addressing it in this edit. A short `note` is
      strongly encouraged ("will handle in a follow-up", "out of scope").

  An entry looks like:

      %{
        "comment_id" => "uuid",
        "action" => "resolve" | "reanchor" | "leave",
        "new_block_id" => "b_xyz",   # required iff action == "reanchor"
        "note" => "..."              # optional human-readable reasoning
      }

  Humans editing through the UI are not required to file dispositions —
  only `actor_type == "agent"` versions are. Humans manually resolving
  threads still use `Aveline.Comments.resolve_comment/2`.
  """

  alias Aveline.Comments.Comment

  @actions ~w(resolve reanchor leave)

  defstruct [:comment_id, :action, :new_block_id, :note]

  @type t :: %__MODULE__{
          comment_id: binary,
          action: String.t(),
          new_block_id: String.t() | nil,
          note: String.t() | nil
        }

  def actions, do: @actions

  @doc """
  Normalize a single raw disposition map (from API params or stored JSON)
  into a `%Disposition{}`. Returns `{:ok, struct}` or `{:error, reason}`.
  """
  def cast(%{} = raw) do
    with {:ok, id}     <- fetch_string(raw, "comment_id"),
         {:ok, action} <- fetch_action(raw),
         {:ok, anchor} <- fetch_anchor(action, raw) do
      {:ok,
       %__MODULE__{
         comment_id: id,
         action: action,
         new_block_id: anchor,
         note: raw["note"] |> to_string_or_nil()
       }}
    end
  end

  def cast(_), do: {:error, :invalid_disposition}

  @doc """
  Validate a list of dispositions against the set of currently-open
  top-level threads and the new version's blocks.

  Returns `:ok` or `{:error, reason}` where reason captures what failed.

  ## Required coverage

  Every comment in `open_thread_ids` must appear exactly once in `dispositions`.
  Reanchor targets must exist in `new_block_ids`.
  """
  def validate(dispositions, open_thread_ids, new_block_ids)
      when is_list(dispositions) and is_list(open_thread_ids) and is_list(new_block_ids) do
    dispo_ids = Enum.map(dispositions, & &1.comment_id)
    open_set = MapSet.new(open_thread_ids)
    dispo_set = MapSet.new(dispo_ids)

    cond do
      length(dispo_ids) != MapSet.size(dispo_set) ->
        {:error, {:duplicate_dispositions, dispo_ids -- Enum.uniq(dispo_ids)}}

      not MapSet.equal?(open_set, dispo_set) ->
        missing = MapSet.difference(open_set, dispo_set) |> MapSet.to_list()
        extra = MapSet.difference(dispo_set, open_set) |> MapSet.to_list()
        {:error, {:disposition_coverage_mismatch, %{missing: missing, extra: extra}}}

      true ->
        validate_reanchors(dispositions, MapSet.new(new_block_ids))
    end
  end

  defp validate_reanchors([], _block_set), do: :ok

  defp validate_reanchors([%__MODULE__{action: "reanchor", new_block_id: id} = d | rest], blocks) do
    if MapSet.member?(blocks, id),
      do: validate_reanchors(rest, blocks),
      else: {:error, {:reanchor_target_missing, d.comment_id, id}}
  end

  defp validate_reanchors([_ | rest], blocks), do: validate_reanchors(rest, blocks)

  @doc """
  Apply a dispositions list to comments inside an Ecto.Multi step.

  `now` and `actor_user_id` parameterize the resolve timestamp + the
  user credited for the resolve. `new_doc_id` is the just-inserted Doc
  version's id — set as `resolved_by_doc_id` on resolves so we can show
  "resolved in v3" badges.
  """
  def apply(repo, dispositions, now, actor_user_id, new_doc_id)
      when is_list(dispositions) do
    Enum.reduce_while(dispositions, {:ok, 0}, fn d, {:ok, n} ->
      case do_apply(repo, d, now, actor_user_id, new_doc_id) do
        {:ok, _} -> {:cont, {:ok, n + 1}}
        :ok      -> {:cont, {:ok, n + 1}}
        {:error, e} -> {:halt, {:error, e}}
      end
    end)
  end

  defp do_apply(repo, %__MODULE__{action: "resolve", comment_id: id}, now, uid, doc_id) do
    repo.get(Comment, id)
    |> case do
      nil -> {:error, {:comment_not_found, id}}
      c ->
        c
        |> Ecto.Changeset.change(%{
          resolved_at: now,
          resolved_by_id: uid,
          resolved_by_doc_id: doc_id
        })
        |> repo.update()
    end
  end

  defp do_apply(repo, %__MODULE__{action: "reanchor", comment_id: id, new_block_id: bid}, _now, _uid, _doc_id) do
    repo.get(Comment, id)
    |> case do
      nil -> {:error, {:comment_not_found, id}}
      c -> c |> Ecto.Changeset.change(%{block_id: bid}) |> repo.update()
    end
  end

  defp do_apply(_repo, %__MODULE__{action: "leave"}, _now, _uid, _doc_id), do: :ok

  @doc "Strip a list of structs back to plain maps for JSON storage on the Doc row."
  def to_json(dispositions) when is_list(dispositions) do
    Enum.map(dispositions, fn d ->
      %{
        "comment_id" => d.comment_id,
        "action" => d.action,
        "new_block_id" => d.new_block_id,
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

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(""), do: nil
  defp to_string_or_nil(s) when is_binary(s), do: s
  defp to_string_or_nil(_), do: nil
end
