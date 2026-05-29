defmodule AvelineWeb.Api.FallbackController do
  @moduledoc """
  Translates context errors into the API error envelope.
  """
  use AvelineWeb, :controller

  alias AvelineWeb.Api.ErrorJSON

  def call(conn, {:error, :unauthorized}) do
    render_error(conn, 401, "unauthorized", "Missing or invalid bearer token.")
  end

  def call(conn, {:error, :forbidden}) do
    render_error(conn, 403, "forbidden", "You don't have access to this workspace.")
  end

  def call(conn, {:error, :workspace_not_found}) do
    render_error(conn, 404, "workspace_not_found", "Workspace not found.")
  end

  def call(conn, {:error, :not_found}) do
    render_error(conn, 404, "not_found", "Resource not found.")
  end

  def call(conn, {:error, :slug_taken}) do
    render_error(conn, 422, "slug_taken", "Slug already in use in this workspace.", field: "slug")
  end

  def call(conn, {:error, :tag_invalid}) do
    render_error(conn, 422, "tag_invalid", "One or more tags are invalid.", field: "tags")
  end

  def call(conn, {:error, %Ecto.Changeset{} = cs}) do
    {code, field, message} = changeset_summary(cs)

    conn
    |> put_status(422)
    |> put_view(json: ErrorJSON)
    |> render(:error, %{
      code: code,
      message: message,
      field: field,
      context: %{errors: changeset_errors(cs)}
    })
  end

  def call(conn, {:error, code, message}) when is_atom(code) and is_binary(message) do
    status =
      case code do
        :unauthorized -> 401
        :forbidden -> 403
        :not_found -> 404
        :workspace_not_found -> 404
        _ -> 422
      end

    render_error(conn, status, Atom.to_string(code), message)
  end

  # Bare `:error` last-resort
  def call(conn, :error) do
    render_error(conn, 500, "internal_error", "Unexpected error.")
  end

  defp render_error(conn, status, code, message, opts \\ []) do
    conn
    |> put_status(status)
    |> put_view(json: ErrorJSON)
    |> render(:error, %{
      code: code,
      message: message,
      field: Keyword.get(opts, :field),
      context: Keyword.get(opts, :context)
    })
  end

  # Pull a useful code + first field out of the changeset.
  defp changeset_summary(%Ecto.Changeset{errors: errors} = cs) do
    errors_map = changeset_errors(cs)

    cond do
      Map.has_key?(errors_map, :slug) and slug_taken?(errors[:slug]) ->
        {"slug_taken", "slug", "Slug already in use in this workspace."}

      Map.has_key?(errors_map, :tags) and tag_invalid?(errors_map.tags) ->
        {"tag_invalid", "tags", "One or more tags are invalid."}

      Map.has_key?(errors_map, :tag_filter) and tag_invalid?(errors_map.tag_filter) ->
        {"tag_invalid", "tag_filter", "One or more tags are invalid."}

      true ->
        {field, _} = List.first(errors) || {nil, nil}
        {"validation_failed", field && Atom.to_string(field), "Validation failed."}
    end
  end

  defp slug_taken?({_msg, opts}) do
    Keyword.get(opts, :constraint) == :unique
  end

  defp slug_taken?(_), do: false

  defp tag_invalid?(messages) when is_list(messages) do
    Enum.any?(messages, &(&1 == "tag_invalid"))
  end

  defp tag_invalid?(_), do: false

  defp changeset_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r/%{(\w+)}/, msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end
end
