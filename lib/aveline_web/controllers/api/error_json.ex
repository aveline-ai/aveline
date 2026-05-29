defmodule AvelineWeb.Api.ErrorJSON do
  @moduledoc """
  Renders the API error envelope.

      { "error": { "code": "...", "message": "...", "field": "...", "context": {} } }
  """

  def error(%{code: code, message: message} = data) do
    %{
      error:
        %{code: code, message: message}
        |> maybe_put(:field, Map.get(data, :field))
        |> maybe_put(:context, Map.get(data, :context))
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ctx) when ctx == %{}, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
