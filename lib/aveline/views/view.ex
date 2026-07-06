defmodule Aveline.Views.View do
  @moduledoc """
  A view: a named, versioned snapshot of the Docs page's display knobs.
  Config tier (the comment test: not commentable, therefore not
  content) — house versioning, soft delete, required description so
  agents know what it's for.

  `config`:
    * `"tags"`     — filter tag slugs (may be empty: all docs)
    * `"group_by"` — a tag scope (renders kanban columns) or nil (list)
    * `"sort"`     — "recent" | "title" (optional; default recent)
    * `"icon"`     — optional emoji for future collapsed-sidebar tiles
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Slug
  alias Aveline.Workspaces.Workspace

  @min_description 6
  @max_description 280
  @sorts ~w(recent title)

  schema "views" do
    field :base_view_id, :binary_id
    field :version_number, :integer, default: 1
    field :name, :string
    field :description, :string
    field :config, :map, default: %{}
    # Placement, not meaning: updated in place, not versioned.
    field :pinned, :boolean, default: false
    field :superseded, :boolean, default: false
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :created_by, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def sorts, do: @sorts

  def insert_changeset(view, attrs) do
    view
    |> cast(attrs, [
      :workspace_id,
      :base_view_id,
      :version_number,
      :name,
      :description,
      :config,
      :pinned,
      :created_by_id
    ])
    |> validate_required([:workspace_id, :base_view_id, :name, :description])
    |> update_change(:name, fn n -> if is_binary(n), do: n |> String.trim() |> String.downcase(), else: n end)
    |> update_change(:description, fn d -> if is_binary(d), do: String.trim(d), else: d end)
    |> validate_name()
    |> validate_length(:description, min: @min_description, max: @max_description)
    |> validate_config()
    |> unique_constraint([:workspace_id, :name],
      name: :views_workspace_id_name_index,
      message: "already exists"
    )
  end

  defp validate_name(changeset) do
    case get_field(changeset, :name) do
      nil ->
        changeset

      name ->
        if Slug.validate(name) == :ok,
          do: changeset,
          else: add_error(changeset, :name, "must be a slug (lowercase letters, digits, dashes)")
    end
  end

  # Normalizes config to known keys only; tag existence and group_by
  # scope validity are checked in the context (they need the workspace).
  defp validate_config(changeset) do
    config = get_field(changeset, :config) || %{}
    tags = Map.get(config, "tags", [])
    group_by = Map.get(config, "group_by")
    sort = Map.get(config, "sort")
    icon = Map.get(config, "icon")

    cond do
      not is_list(tags) or Enum.any?(tags, &(not is_binary(&1))) ->
        add_error(changeset, :config, "tags must be a list of tag slugs")

      not (is_nil(group_by) or (is_binary(group_by) and group_by != "")) ->
        add_error(changeset, :config, "group_by must be a tag scope or null")

      not (is_nil(sort) or sort in @sorts) ->
        add_error(changeset, :config, "sort must be one of #{Enum.join(@sorts, ", ")}")

      not (is_nil(icon) or is_binary(icon)) ->
        add_error(changeset, :config, "icon must be a string")

      true ->
        clean =
          %{"tags" => tags}
          |> then(fn c -> if group_by, do: Map.put(c, "group_by", group_by), else: c end)
          |> then(fn c -> if sort, do: Map.put(c, "sort", sort), else: c end)
          |> then(fn c -> if icon, do: Map.put(c, "icon", icon), else: c end)

        put_change(changeset, :config, clean)
    end
  end
end
