defmodule Aveline.Pagination do
  @moduledoc """
  Single source of truth for paginated-list sizes. Picked to fit roughly
  one screenful of mixed-density rows (doc cards, event lines) without
  needing horizontal scroll — and small enough that "Load more" feels
  meaningful rather than ceremonial.

  Bump here only; LVs reference `default_page_size/0`.
  """

  @default_page_size 25

  def default_page_size, do: @default_page_size
end
