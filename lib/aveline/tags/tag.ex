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
    field :base_tag_id, :binary_id
    field :version_number, :integer, default: 1
    field :slug, :string
    field :description, :string
    # Optional #rrggbb; UI falls back to the default tag color when nil.
    field :color, :string
    # Mechanism vs intent (house model): superseded = a newer version
    # row replaced this one; deleted_at (+deleted_by) = a human deleted
    # the tag.
    field :superseded, :boolean, default: false
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :created_by, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def min_description, do: @min_description
  def max_description, do: @max_description

  def create_changeset(tag, attrs) do
    tag
    |> cast(attrs, [
      :workspace_id,
      :base_tag_id,
      :version_number,
      :slug,
      :description,
      :color,
      :created_by_id
    ])
    |> validate_required([:workspace_id, :base_tag_id, :slug, :description])
    |> normalize_slug()
    |> validate_slug_format()
    |> validate_description()
    |> validate_color()
    |> unique_constraint([:workspace_id, :slug],
      name: :tags_workspace_id_slug_index,
      message: "already exists"
    )
  end

  defp validate_color(changeset) do
    changeset
    |> update_change(:color, fn c ->
      if is_binary(c), do: c |> String.trim() |> String.downcase(), else: c
    end)
    |> validate_format(:color, ~r/^#[0-9a-f]{6}$/, message: "must be a hex color like #e09150")
  end

  defp normalize_slug(changeset) do
    update_change(changeset, :slug, fn s ->
      if is_binary(s), do: s |> String.trim() |> String.downcase(), else: s
    end)
  end

  # Plain tag (`runbook`) or scoped tag (`status:todo`) — one `:` max,
  # both halves ordinary slugs. Scoped tags are enums: a doc carries at
  # most one tag per scope (enforced on the doc write path).
  defp validate_slug_format(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        changeset

      slug ->
        valid? =
          case String.split(slug, ":") do
            [plain] -> Slug.validate(plain) == :ok
            [scope, value] -> Slug.validate(scope) == :ok and Slug.validate(value) == :ok
            _ -> false
          end

        if valid?, do: changeset, else: add_error(changeset, :slug, "tag_invalid")
    end
  end

  defp validate_description(changeset) do
    changeset
    |> update_change(:description, fn d -> if is_binary(d), do: String.trim(d), else: d end)
    |> validate_length(:description, min: @min_description, max: @max_description)
  end
end
