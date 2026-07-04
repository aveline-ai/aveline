defmodule Aveline.Blocks.Inline do
  @moduledoc """
  Inline spans — the structured rich-text inside paragraphs, list items,
  callouts, and table cells.

  A span is a map with:
    * `"text"` (required, string)
    * `"marks"` (optional, list of "bold" | "italic" | "code" | "strike")
    * `"link"` (optional) — external `%{"href" => url}` OR internal
      `%{"doc_id" => uuid}` (another doc in the workspace, by
      base_doc_id). One field, so a span can't carry both. The API also
      accepts `%{"doc" => slug}`; the Docs context resolves it to
      `doc_id` before validation reaches here. Reads enrich internal
      links with a `"target"` echo (slug/title/deleted) — never
      persisted; normalization here rebuilds the link from known fields
      so a pasted echo is stripped automatically.

  The span text is the author's words — never the target's live title.
  Content is authored and versioned; the echo carries the current title
  for renderers that want it.

  No nesting. No HTML escaping issues. Renderer maps each span to a
  `<span>` with classes per mark.
  """

  @uuid_re ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

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

  defp validate_link(%{"link" => nil}), do: {:ok, nil}

  defp validate_link(%{"link" => %{} = link}) do
    external? = Map.has_key?(link, "href")
    internal? = Map.has_key?(link, "doc") or Map.has_key?(link, "doc_id")

    cond do
      external? and internal? ->
        {:error, "span.link is external {href} or internal {doc_id}, not both"}

      internal? ->
        validate_internal_link(link)

      is_binary(link["href"]) and link["href"] != "" ->
        {:ok, %{"href" => link["href"]}}

      external? ->
        {:error, "span.link.href must be a non-empty string"}

      true ->
        {:error, "span.link must be {href: url} or {doc_id: uuid}"}
    end
  end

  defp validate_link(%{"link" => _}), do: {:error, "span.link must be {href: url} or {doc_id: uuid}"}
  defp validate_link(%{}), do: {:ok, nil}

  defp validate_internal_link(%{"doc_id" => doc_id}) when is_binary(doc_id) do
    if Regex.match?(@uuid_re, doc_id),
      do: {:ok, %{"doc_id" => String.downcase(doc_id)}},
      else:
        {:error,
         "span.link.doc_id must be a UUID (the target's base_doc_id); or pass link: {doc: <slug>} and the server resolves it"}
  end

  defp validate_internal_link(_) do
    {:error,
     "span.link.doc_id must be a UUID (the target's base_doc_id); or pass link: {doc: <slug>} and the server resolves it"}
  end

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
