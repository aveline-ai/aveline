defmodule Aveline.Blocks.Document do
  @moduledoc """
  Apply a sequence of operations to a list of blocks.

  Pure: no Repo, no PubSub. Returns the new blocks array or an error
  tuple. Errors are returned as `{:error, reason_string, index}` where
  `index` is the position of the failing op in the input list so the
  caller can build a precise error envelope.
  """

  alias Aveline.Blocks.Block
  alias Aveline.Blocks.Operation

  @doc """
  Validate + apply a list of ops to a blocks array. Either every op
  succeeds or none do (all-or-nothing semantics — the caller is expected
  to wrap this in a transaction together with the version insert).
  """
  def apply_ops(blocks, ops) when is_list(blocks) and is_list(ops) do
    ops
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, blocks}, fn {raw_op, idx}, {:ok, current} ->
      with {:ok, op} <- Operation.validate(raw_op),
           {:ok, next} <- apply_op(current, op) do
        {:cont, {:ok, next}}
      else
        {:error, reason} -> {:halt, {:error, reason, idx}}
        {:error, _, _} = err -> {:halt, err}
      end
    end)
  end

  def apply_ops(_, _), do: {:error, "blocks and ops must both be lists", 0}

  # ===== Per-op apply =====

  defp apply_op(blocks, %{"op" => "append_block", "block" => block}) do
    if id_exists?(blocks, block["id"]) do
      {:error, "block id #{block["id"]} already exists; cannot append"}
    else
      {:ok, blocks ++ [block]}
    end
  end

  defp apply_op(blocks, %{"op" => "insert_block", "after" => after_id, "block" => block}) do
    cond do
      id_exists?(blocks, block["id"]) ->
        {:error, "block id #{block["id"]} already exists; cannot insert"}

      not id_exists?(blocks, after_id) ->
        {:error, "insert_block.after #{after_id} not found"}

      true ->
        {:ok, insert_after(blocks, after_id, block)}
    end
  end

  defp apply_op(blocks, %{"op" => "modify_block", "id" => id, "patch" => patch}) do
    case find_block(blocks, id) do
      nil ->
        {:error, "modify_block target #{id} not found"}

      existing ->
        case Block.validate_patch(existing, patch) do
          {:ok, updated} -> {:ok, replace_block(blocks, id, updated)}
          err -> err
        end
    end
  end

  defp apply_op(blocks, %{"op" => "delete_block", "id" => id}) do
    if id_exists?(blocks, id) do
      {:ok, Enum.reject(blocks, &(&1["id"] == id))}
    else
      {:error, "delete_block target #{id} not found"}
    end
  end

  defp apply_op(blocks, %{"op" => "move_block", "id" => id, "after" => after_id}) do
    cond do
      not id_exists?(blocks, id) ->
        {:error, "move_block target #{id} not found"}

      is_binary(after_id) and not id_exists?(blocks, after_id) ->
        {:error, "move_block.after #{after_id} not found"}

      after_id == id ->
        {:error, "move_block.after cannot equal id"}

      true ->
        block = find_block(blocks, id)
        without = Enum.reject(blocks, &(&1["id"] == id))
        {:ok, if(after_id == nil, do: [block | without], else: insert_after(without, after_id, block))}
    end
  end

  # ===== Helpers =====

  defp id_exists?(blocks, id) do
    Enum.any?(blocks, &(&1["id"] == id))
  end

  defp find_block(blocks, id) do
    Enum.find(blocks, &(&1["id"] == id))
  end

  defp insert_after(blocks, after_id, new_block) do
    Enum.reduce(blocks, [], fn b, acc ->
      if b["id"] == after_id, do: acc ++ [b, new_block], else: acc ++ [b]
    end)
  end

  defp replace_block(blocks, id, updated) do
    Enum.map(blocks, fn b -> if b["id"] == id, do: updated, else: b end)
  end
end
