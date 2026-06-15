defmodule Aveline.Tags.Tag do
  @moduledoc """
  Workspace-scoped tag with required description. The tag's `slug` is
  what appears on doc rows in `docs.tags[]`; descriptions feed into LLM
  search and the Tags management page.
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Slug
  alias Aveline.Workspaces.Workspace

  @min_description 6
  @max_description 280

  schema "tags" do
    field :slug, :string
    field :description, :string

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :created_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def min_description, do: @min_description
  def max_description, do: @max_description

  def create_changeset(tag, attrs) do
    tag
    |> cast(attrs, [:workspace_id, :slug, :description, :created_by_id])
    |> validate_required([:workspace_id, :slug, :description])
    |> normalize_slug()
    |> validate_slug_format()
    |> validate_description()
    |> unique_constraint([:workspace_id, :slug],
      name: :tags_workspace_id_slug_index,
      message: "already exists"
    )
  end

  def update_changeset(tag, attrs) do
    tag
    |> cast(attrs, [:slug, :description])
    |> normalize_slug()
    |> validate_required([:slug, :description])
    |> validate_slug_format()
    |> validate_description()
    |> unique_constraint([:workspace_id, :slug],
      name: :tags_workspace_id_slug_index,
      message: "already exists"
    )
  end

  defp normalize_slug(changeset) do
    update_change(changeset, :slug, fn s ->
      if is_binary(s), do: s |> String.trim() |> String.downcase(), else: s
    end)
  end

  defp validate_slug_format(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        changeset

      slug ->
        case Slug.validate(slug) do
          :ok -> changeset
          {:error, _} -> add_error(changeset, :slug, "lowercase letters, digits, hyphens only")
        end
    end
  end

  defp validate_description(changeset) do
    changeset
    |> update_change(:description, fn d -> if is_binary(d), do: String.trim(d), else: d end)
    |> validate_length(:description, min: @min_description, max: @max_description)
  end
end
