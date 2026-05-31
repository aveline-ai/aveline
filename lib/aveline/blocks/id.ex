defmodule Aveline.Blocks.Id do
  @moduledoc """
  Block ID minting. Block IDs are URL-safe random strings prefixed by
  type (`b_` for blocks, `li_` for list items) so they're recognizable in
  logs and URLs.

      iex> Aveline.Blocks.Id.mint_block()
      "b_QkN4dGV4dF8xMjM0NTY3OA"
  """

  @block_prefix "b_"
  @list_item_prefix "li_"
  @random_bytes 16

  def mint_block, do: @block_prefix <> rand22()
  def mint_list_item, do: @list_item_prefix <> rand22()

  def valid_block_id?(id) when is_binary(id), do: String.starts_with?(id, @block_prefix)
  def valid_block_id?(_), do: false

  def valid_list_item_id?(id) when is_binary(id), do: String.starts_with?(id, @list_item_prefix)
  def valid_list_item_id?(_), do: false

  defp rand22 do
    :crypto.strong_rand_bytes(@random_bytes)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 22)
  end
end
