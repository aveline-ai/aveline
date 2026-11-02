defmodule Aveline.Blocks.Builder do
  @moduledoc """
  Tiny builders for hand-written block lists: the workspace templates and
  Aveline's guide. One set, shared, so the two stay matched in shape and
  a block that validates in one validates in the other.

  `import Aveline.Blocks.Builder` and write `para([b("Bold. "), t("Plain.")])`.
  Ids are left off: the server mints them on write, and the guide numbers
  its own.
  """

  @doc "A plain span."
  def t(text) when is_binary(text), do: %{"text" => text}

  @doc "A bold span."
  def b(text) when is_binary(text), do: %{"text" => text, "marks" => ["bold"]}

  @doc "A code span."
  def code_t(text) when is_binary(text), do: %{"text" => text, "marks" => ["code"]}

  @doc "A paragraph from a list of spans, or one span."
  def para(spans) when is_list(spans), do: %{"type" => "paragraph", "content" => spans}
  def para(%{} = span), do: %{"type" => "paragraph", "content" => [span]}

  @doc "A level-2 heading."
  def h2(text) when is_binary(text), do: %{"type" => "heading", "level" => 2, "text" => text}

  @doc "An unordered list; each item is a list of spans."
  def ul(items) when is_list(items),
    do: %{"type" => "list", "ordered" => false, "items" => Enum.map(items, &%{"content" => &1})}

  @doc "An ordered list; each item is a list of spans."
  def ol(items) when is_list(items),
    do: %{"type" => "list", "ordered" => true, "items" => Enum.map(items, &%{"content" => &1})}
end
