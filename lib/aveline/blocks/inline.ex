defmodule Aveline.Blocks.Inline do
  @moduledoc """
  Inline spans — the structured rich-text inside paragraphs, list items,
  callouts, and table cells.

  A span is a map with:
    * `"text"` (required, string)
    * `"marks"` (optional, list of "bold" | "italic" | "code" | "strike")
    * `"link"` (optional, `%{"href" => string}`)

  No nesting. No HTML escaping issues. Renderer maps each span to a
  `<span>` with classes per mark.
  """

  @marks ~w(bold italic code strike)
  @max_marks length(@marks)

  @doc """
  Validate + normalize a list of spans. Returns `{:ok, normalized}` or
  `{:error, reason}`.
  """
  def validate_spans(spans) when is_list(spans) do
    Enum.reduce_while(spans, {:ok, []}, fn span, {:ok, acc} ->
      case validate_span(span) do
        {:ok, normalized} -> {:cont, {:ok, acc ++ [normalized]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  def validate_spans(_), do: {:error, "inline content must be a list of spans"}

  defp validate_span(%{} = span) do
    with {:ok, text} <- validate_text(span),
         {:ok, marks} <- validate_marks(span),
         {:ok, link} <- validate_link(span) do
      out = %{"text" => text}
      out = if marks == [], do: out, else: Map.put(out, "marks", marks)
      out = if link == nil, do: out, else: Map.put(out, "link", link)
      {:ok, out}
    end
  end

  defp validate_span(_), do: {:error, "span must be an object"}

  defp validate_text(%{"text" => t}) when is_binary(t), do: {:ok, t}
  defp validate_text(_), do: {:error, "span.text required (string)"}

  defp validate_marks(%{"marks" => marks}) when is_list(marks) do
    cond do
      length(marks) > @max_marks ->
        {:error, "span.marks may contain at most #{@max_marks} entries"}

      Enum.any?(marks, fn m -> m not in @marks end) ->
        {:error, "span.marks must be a subset of #{inspect(@marks)}"}

      true ->
        {:ok, Enum.uniq(marks)}
    end
  end

  defp validate_marks(%{}), do: {:ok, []}

  defp validate_link(%{"link" => %{"href" => href}}) when is_binary(href) do
    if href == "", do: {:error, "span.link.href cannot be empty"}, else: {:ok, %{"href" => href}}
  end

  defp validate_link(%{"link" => nil}), do: {:ok, nil}
  defp validate_link(%{"link" => _}), do: {:error, "span.link must be %{href: ...}"}
  defp validate_link(%{}), do: {:ok, nil}

  @doc "Best-effort plain-text representation of inline spans (for summaries, search)."
  def to_text(spans) when is_list(spans) do
    spans
    |> Enum.map_join("", fn
      %{"text" => t} -> t
      _ -> ""
    end)
  end

  def to_text(_), do: ""

  def marks, do: @marks
end
