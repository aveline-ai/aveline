defmodule AvelineWeb.ChartRenderer do
  @moduledoc """
  Validates a chart block's read-time `result` echo against its viz and
  produces the spec the client-side ECharts hook renders. Pure — all
  querying already happened in `Docs.enrich_blocks`; all drawing happens
  in the browser (assets/js/app.js, `Chart` hook, lazily loading the
  self-hosted ECharts chunk).

  Every failure is a rendered state, not a raise: bad column names,
  non-numeric y values, empty results all come back as `{:error, msg}`
  for the block component to show.
  """

  @doc "Returns {:ok, spec_map_for_the_hook} | {:error, message}."
  def spec(%{"error" => msg}, _viz), do: {:error, msg}

  def spec(%{"columns" => cols, "rows" => rows}, %{"type" => type} = viz)
      when type in ["line", "bar"] do
    x = viz["x"]
    y = viz["y"]

    cond do
      x not in cols ->
        {:error, "column #{inspect(x)} not in result (has: #{Enum.join(cols, ", ")})"}

      y not in cols ->
        {:error, "column #{inspect(y)} not in result (has: #{Enum.join(cols, ", ")})"}

      rows == [] ->
        {:error, "query returned no rows"}

      true ->
        yi = Enum.find_index(cols, &(&1 == y))

        if numeric_series?(rows, yi),
          do: {:ok, %{"columns" => cols, "rows" => rows, "viz" => viz}},
          else: {:error, "column #{inspect(y)} must be numeric for line/bar charts"}
    end
  end

  def spec(%{"columns" => cols, "rows" => rows}, %{"type" => "combo"} = viz) do
    x = viz["x"]
    ys = Enum.map(viz["series"] || [], & &1["y"])

    missing = Enum.filter([x | ys], &(&1 not in cols))

    cond do
      missing != [] ->
        {:error,
         "column#{if length(missing) > 1, do: "s"} #{Enum.map_join(missing, ", ", &inspect/1)} not in result (has: #{Enum.join(cols, ", ")})"}

      rows == [] ->
        {:error, "query returned no rows"}

      true ->
        bad_y =
          Enum.find(ys, fn y ->
            yi = Enum.find_index(cols, &(&1 == y))
            not numeric_series?(rows, yi)
          end)

        if bad_y,
          do: {:error, "column #{inspect(bad_y)} must be numeric for combo charts"},
          else: {:ok, %{"columns" => cols, "rows" => rows, "viz" => viz}}
    end
  end

  def spec(_result, _viz), do: {:error, "nothing to render"}

  # A plottable numeric series: nulls are allowed (ECharts renders them
  # as gaps — e.g. a forecast column that's null over the actual range),
  # every non-null value must be numeric, and at least one must be
  # present (an all-null column is nothing to plot).
  defp numeric_series?(rows, yi) do
    vals = Enum.map(rows, &Enum.at(&1, yi))
    present = Enum.reject(vals, &is_nil/1)
    present != [] and Enum.all?(present, &numeric?/1)
  end

  defp numeric?(v) when is_number(v), do: true

  defp numeric?(v) when is_binary(v) do
    match?({_, ""}, Float.parse(v))
  end

  defp numeric?(_), do: false
end
