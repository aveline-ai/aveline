defmodule AvelineWeb.ChartRenderer do
  @moduledoc """
  Turns a chart block's read-time `result` echo into markup: an HTML
  table, or a Contex-rendered SVG line/bar chart. Pure — takes the
  echoed maps, returns safe HTML; all querying already happened in
  `Docs.enrich_blocks`.

  Every failure is a rendered state, not a raise: bad column names,
  non-numeric values, unparseable x values all come back as
  `{:error, msg}` for the block component to show.
  """

  alias Contex.{BarChart, Dataset, LinePlot, Plot}

  @width 640
  @height 260

  @doc "Returns {:ok, {:safe, iodata}} | {:error, message}."
  def render(%{"error" => msg}, _viz), do: {:error, msg}

  def render(%{"columns" => cols, "rows" => rows}, %{"type" => type} = viz)
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
        xi = Enum.find_index(cols, &(&1 == x))
        yi = Enum.find_index(cols, &(&1 == y))
        points = Enum.map(rows, fn row -> {Enum.at(row, xi), Enum.at(row, yi)} end)
        build(type, x, y, points)
    end
  end

  def render(_result, _viz), do: {:error, "nothing to render"}

  # ===== chart building =====

  defp build(type, x_name, y_name, points) do
    with {:ok, ys} <- numeric_column(y_name, Enum.map(points, &elem(&1, 1))) do
      case type do
        "bar" ->
          # Categories are strings; any x works.
          data = Enum.zip(Enum.map(points, &to_string(elem(&1, 0))), ys) |> Enum.map(&Tuple.to_list/1)
          plot(BarChart, data, x_name, y_name, %{category_col: x_name, value_cols: [y_name]})

        "line" ->
          # LinePlot needs an ordered numeric/time x axis.
          case parse_xs(Enum.map(points, &elem(&1, 0))) do
            {:ok, xs} ->
              data = Enum.zip(xs, ys) |> Enum.map(&Tuple.to_list/1)
              plot(LinePlot, data, x_name, y_name, %{x_col: x_name, y_cols: [y_name]})

            :error ->
              {:error,
               "line charts need a numeric or date/datetime x column; #{inspect(x_name)} isn't (try viz type \"bar\")"}
          end
      end
    end
  end

  defp plot(module, data, x_name, y_name, mapping) do
    svg =
      data
      |> Dataset.new([x_name, y_name])
      |> Plot.new(module, @width, @height, mapping: Map.new(mapping))
      # default_style: false — Contex otherwise embeds a <style> block
      # (text{fill:black} line{stroke:black}) whose rules are DOCUMENT
      # global, blacking out every inline SVG icon on the page. Plot.new
      # ignores the option in attrs, so set the struct field directly.
      # Our scoped .chart-plot CSS carries the styling instead.
      |> struct!(default_style: false)
      |> Plot.to_svg()

    {:ok, svg}
  rescue
    e -> {:error, "chart rendering failed: #{Exception.message(e)}"}
  end

  defp numeric_column(name, values) do
    nums = Enum.map(values, &to_number/1)

    if Enum.all?(nums, &is_number/1),
      do: {:ok, nums},
      else: {:error, "column #{inspect(name)} must be numeric for line/bar charts"}
  end

  defp to_number(v) when is_number(v), do: v

  defp to_number(v) when is_binary(v) do
    case Float.parse(v) do
      {f, ""} -> f
      _ -> nil
    end
  end

  defp to_number(_), do: nil

  # x values arrive JSON-safe (dates already ISO strings). Accept
  # numbers, ISO dates, and ISO datetimes; reject mixed/other.
  defp parse_xs(values) do
    parsed = Enum.map(values, &parse_x/1)
    if Enum.any?(parsed, &is_nil/1), do: :error, else: {:ok, parsed}
  end

  defp parse_x(v) when is_number(v), do: v

  defp parse_x(v) when is_binary(v) do
    case Date.from_iso8601(v) do
      {:ok, d} ->
        NaiveDateTime.new!(d, ~T[00:00:00])

      _ ->
        case NaiveDateTime.from_iso8601(v) do
          {:ok, ndt} ->
            ndt

          _ ->
            case DateTime.from_iso8601(v) do
              {:ok, dt, _} ->
                dt

              _ ->
                case Float.parse(v) do
                  {f, ""} -> f
                  _ -> nil
                end
            end
        end
    end
  end

  defp parse_x(_), do: nil
end
