defmodule AvelineWeb.Api.FallbackController do
  @moduledoc """
  Translates context-layer errors into the canonical API envelope.

  Controllers can return `{:error, code_atom}` (HTTP-level) or
  `{:error, {tag, payload}}` (business-level, e.g. disposition errors
  from the comments context) and this fallback maps them into a clean
  envelope the agent can branch on. See ErrorCodes for the catalog.
  """
  use AvelineWeb, :controller

  import AvelineWeb.Api.Envelope, only: [err: 4, err: 5]

  # ===== HTTP-level (auth, scope) =====

  def call(conn, {:error, :unauthorized}),
    do: err(conn, 401, "unauthorized", "Missing or invalid bearer token.")

  def call(conn, {:error, :forbidden}),
    do: err(conn, 403, "forbidden", "You don't have access to this resource.")

  def call(conn, {:error, :workspace_not_found}),
    do: err(conn, 404, "workspace_not_found", "Workspace not found.")

  def call(conn, {:error, :not_found}),
    do: err(conn, 404, "not_found", "Resource not found.")

  # ===== Validation (changesets) =====

  def call(conn, {:error, %Ecto.Changeset{} = cs}) do
    {code, field, message} = changeset_summary(cs)

    err(conn, 422, code, message, %{errors: changeset_errors(cs)} |> maybe_add(:field, field))
  end

  # ===== Tag-specific =====

  def call(conn, {:error, :slug_taken}),
    do: err(conn, 422, "slug_taken", "Slug already in use.", %{field: "slug"})

  def call(conn, {:error, :tag_invalid}),
    do: err(conn, 422, "tag_invalid", "One or more tags are invalid.", %{field: "tags"})

  def call(conn, {:error, {:unknown_tags, slugs}}),
    do:
      err(conn, 422, "unknown_tags", "One or more tags aren't defined in this workspace yet. Create them first.", %{
        unknown_tags: slugs
      })

  # ===== API keys =====

  def call(conn, {:error, :last_key}),
    do:
      err(conn, 422, "last_key", "That's the only active key on this account. Create a replacement first, then revoke this one.")

  # ===== List / search params =====

  def call(conn, {:error, {:list_param_invalid, message}}),
    do: err(conn, 422, "list_param_invalid", message)

  def call(conn, {:error, {:unknown_authors, usernames}}),
    do:
      err(conn, 422, "unknown_authors", "One or more authors aren't members of this workspace.", %{
        unknown_authors: usernames
      })

  # ===== Comment dispositions =====

  def call(conn, {:error, {:disposition_missing, missing}}),
    do:
      err(
        conn,
        422,
        "disposition_missing",
        "Open comments anchored to touched blocks must be dispositioned (resolve / reanchor / leave).",
        %{missing: missing}
      )

  def call(conn, {:error, {:duplicate_dispositions, ids}}),
    do: err(conn, 422, "duplicate_dispositions", "A comment was dispositioned more than once.", %{duplicate_ids: ids})

  def call(conn, {:error, {:leave_on_deleted_block, comment_id}}),
    do:
      err(
        conn,
        422,
        "leave_on_deleted_block",
        "A comment whose block was deleted cannot be left open. Resolve it (with a reply) or reanchor it.",
        %{comment_id: comment_id}
      )

  def call(conn, {:error, {:reanchor_target_missing, comment_id, block_id}}),
    do:
      err(conn, 422, "reanchor_target_missing", "Reanchor target block does not exist in the new version's blocks.", %{
        comment_id: comment_id,
        new_block_id: block_id
      })

  def call(conn, {:error, {:invalid_action, action}}),
    do:
      err(conn, 422, "invalid_disposition_action", "Disposition action must be one of: resolve, reanchor, leave.", %{
        got: action
      })

  def call(conn, {:error, {:missing_field, field}}),
    do: err(conn, 422, "validation_failed", "Missing required field: #{field}.", %{field: field})

  def call(conn, {:error, {:comment_not_found, id}}),
    do: err(conn, 422, "comment_not_found", "Dispositioned comment no longer exists.", %{comment_id: id})

  def call(conn, {:error, :invalid_disposition}),
    do: err(conn, 422, "validation_failed", "Disposition entry must be an object.")

  # ===== Doc-specific =====

  def call(conn, {:error, :self_kudos, msg}),
    do: err(conn, 422, "self_kudos", msg)

  def call(conn, {:error, :not_user_deleted}),
    do:
      err(
        conn,
        422,
        "not_user_deleted",
        "Doc was not user-deleted (it's the current live version or was superseded by a new version)."
      )

  def call(conn, {:error, :orientation_undeletable}),
    do:
      err(
        conn,
        422,
        "orientation_undeletable",
        "The workspace orientation doc can't be deleted — every workspace keeps one. Edit it instead."
      )

  def call(conn, {:error, :pin_limit_reached}),
    do:
      err(
        conn,
        422,
        "pin_limit_reached",
        "All #{Aveline.Docs.pin_limit()} home-page pin slots are taken. Unpin one first — pins are the curated front page, keep them scarce."
      )

  def call(conn, {:error, {:pin_slot_taken, slot, occupant}}),
    do:
      err(
        conn,
        422,
        "pin_slot_taken",
        "Pin slot #{slot} is held by \"#{occupant}\". Unpin or re-slot it first — slots never displace silently.",
        %{slot: slot, occupant: occupant}
      )

  def call(conn, {:error, {:tag_scope_conflict, scope, tags}}),
    do:
      err(
        conn,
        422,
        "tag_scope_conflict",
        "A doc can carry at most one tag per scope — the set has #{Enum.join(tags, " and ")}. Scoped tags (#{scope}:*) are mutually exclusive options.",
        %{scope: scope, tags: tags}
      )

  # ===== Workspace memberships =====

  def call(conn, {:error, :self_remove}),
    do: err(conn, 422, "self_remove", "You can't remove yourself from a workspace.")

  def call(conn, {:error, :already_member}),
    do: err(conn, 422, "already_member", "User is already a member of this workspace.")

  def call(conn, {:error, :not_member}),
    do: err(conn, 422, "not_member", "User is not a member of this workspace.")

  # ===== Generic tagged code =====

  # Bare string error message — most commonly from Block / Operation
  # validation, which can't always produce a structured changeset.
  def call(conn, {:error, message}) when is_binary(message),
    do: err(conn, 422, "validation_failed", message)

  def call(conn, {:error, code, message}) when is_atom(code) and is_binary(message) do
    status =
      case code do
        :unauthorized -> 401
        :forbidden -> 403
        :not_found -> 404
        :workspace_not_found -> 404
        _ -> 422
      end

    err(conn, status, Atom.to_string(code), message)
  end

  # ===== Last resort =====

  def call(conn, :error),
    do: err(conn, 500, "internal_error", "Unexpected error.")

  def call(conn, {:error, %{__struct__: _} = struct}),
    do: err(conn, 500, "internal_error", "Unexpected error.", %{kind: inspect(struct.__struct__)})

  def call(conn, _other),
    do: err(conn, 500, "internal_error", "Unexpected error.")

  # ===== Helpers =====

  defp changeset_summary(%Ecto.Changeset{errors: errors} = cs) do
    errors_map = changeset_errors(cs)

    cond do
      Map.has_key?(errors_map, :slug) and slug_taken?(errors[:slug]) ->
        {"slug_taken", "slug", "Slug already in use."}

      Map.has_key?(errors_map, :tags) and tag_invalid?(errors_map.tags) ->
        {"tag_invalid", "tags", "One or more tags are invalid."}

      Map.has_key?(errors_map, :tag_filter) and tag_invalid?(errors_map.tag_filter) ->
        {"tag_invalid", "tag_filter", "One or more tags are invalid."}

      Map.has_key?(errors_map, :slug) and tag_invalid?(errors_map.slug) ->
        {"tag_invalid", "slug", "Tag slug must be lowercase letters, digits, hyphens."}

      true ->
        {field, _} = List.first(errors) || {nil, nil}
        {"validation_failed", field && Atom.to_string(field), "Validation failed."}
    end
  end

  defp slug_taken?({_msg, opts}), do: Keyword.get(opts, :constraint) == :unique
  defp slug_taken?(_), do: false

  defp tag_invalid?(messages) when is_list(messages),
    do: Enum.any?(messages, &(&1 == "tag_invalid"))

  defp tag_invalid?(_), do: false

  defp changeset_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r/%{(\w+)}/, msg, fn _, k ->
        opts |> Keyword.get(String.to_existing_atom(k), k) |> to_string()
      end)
    end)
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
