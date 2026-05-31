defmodule Aveline.Blocks.Operation do
  @moduledoc """
  The five mutation operations + their validators.

  Operations are tagged maps with string keys (matching the JSON wire
  format):

    append_block:  %{"op" => "append_block", "block" => %{...}, "metadata"? => %{}}
    insert_block:  %{"op" => "insert_block", "after" => "b_xxx",
                     "block" => %{...}, "metadata"? => %{}}
    modify_block:  %{"op" => "modify_block", "id" => "b_xxx",
                     "patch" => %{...}, "metadata"? => %{}}
    delete_block:  %{"op" => "delete_block", "id" => "b_xxx",
                     "metadata"? => %{}}
    move_block:    %{"op" => "move_block", "id" => "b_xxx",
                     "after" => "b_yyy" | null,
                     "metadata"? => %{}}

  The optional `metadata` field on each op is for diff_intent + future
  per-op annotations.

  This module only validates the *shape* of an op. Whether referenced
  IDs exist is checked by `Aveline.Blocks.Document.apply_ops/2`.
  """

  alias Aveline.Blocks.Block
  alias Aveline.Blocks.Id

  @ops ~w(append_block insert_block modify_block delete_block move_block)

  def ops, do: @ops

  @doc """
  Validate a single op. Returns `{:ok, normalized}` or `{:error, reason}`.
  The block embedded in append/insert ops is itself validated; its `id`
  is minted if absent.
  """
  def validate(%{"op" => op_name} = op) when op_name in @ops do
    metadata = Map.get(op, "metadata")

    with {:ok, metadata} <- validate_metadata(metadata),
         {:ok, normalized} <- validate_specific(op_name, op) do
      out =
        normalized
        |> Map.put("op", op_name)
        |> maybe_put_metadata(metadata)

      {:ok, out}
    end
  end

  def validate(%{"op" => op_name}) when is_binary(op_name) do
    {:error, "unknown op #{inspect(op_name)}; expected one of #{inspect(@ops)}"}
  end

  def validate(_), do: {:error, "operation requires \"op\" field"}

  defp validate_specific("append_block", %{"block" => raw_block}) do
    with {:ok, block} <- Block.validate(raw_block, mint_id?: true) do
      {:ok, %{"block" => block}}
    end
  end

  defp validate_specific("append_block", _), do: {:error, "append_block requires \"block\""}

  defp validate_specific("insert_block", %{"block" => raw_block, "after" => after_id})
       when is_binary(after_id) do
    cond do
      not Id.valid_block_id?(after_id) ->
        {:error, "insert_block.after must be a valid block id"}

      true ->
        case Block.validate(raw_block, mint_id?: true) do
          {:ok, block} -> {:ok, %{"after" => after_id, "block" => block}}
          err -> err
        end
    end
  end

  defp validate_specific("insert_block", _) do
    {:error, "insert_block requires \"block\" and \"after\""}
  end

  defp validate_specific("modify_block", %{"id" => id, "patch" => patch})
       when is_binary(id) and is_map(patch) do
    if Id.valid_block_id?(id),
      do: {:ok, %{"id" => id, "patch" => patch}},
      else: {:error, "modify_block.id must be a valid block id"}
  end

  defp validate_specific("modify_block", _) do
    {:error, "modify_block requires \"id\" and \"patch\""}
  end

  defp validate_specific("delete_block", %{"id" => id}) when is_binary(id) do
    if Id.valid_block_id?(id),
      do: {:ok, %{"id" => id}},
      else: {:error, "delete_block.id must be a valid block id"}
  end

  defp validate_specific("delete_block", _), do: {:error, "delete_block requires \"id\""}

  defp validate_specific("move_block", %{"id" => id} = op) when is_binary(id) do
    after_id =
      case Map.get(op, "after") do
        nil -> nil
        s when is_binary(s) -> s
        _ -> :error
      end

    cond do
      after_id == :error ->
        {:error, "move_block.after must be a block id or null"}

      not Id.valid_block_id?(id) ->
        {:error, "move_block.id must be a valid block id"}

      is_binary(after_id) and not Id.valid_block_id?(after_id) ->
        {:error, "move_block.after must be a valid block id"}

      true ->
        {:ok, %{"id" => id, "after" => after_id}}
    end
  end

  defp validate_specific("move_block", _), do: {:error, "move_block requires \"id\""}

  defp validate_metadata(nil), do: {:ok, nil}
  defp validate_metadata(m) when is_map(m), do: {:ok, m}
  defp validate_metadata(_), do: {:error, "operation.metadata must be an object"}

  defp maybe_put_metadata(map, nil), do: map
  defp maybe_put_metadata(map, m) when m == %{}, do: map
  defp maybe_put_metadata(map, m), do: Map.put(map, "metadata", m)
end
