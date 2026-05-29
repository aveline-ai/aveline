defmodule Aveline.Views.View do
  @moduledoc false
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Slug
  alias Aveline.Workspaces.Workspace

  @scopes ~w(personal team)

  @derive {Jason.Encoder,
           only: [
             :id,
             :slug,
             :name,
             :tag_filter,
             :description,
             :scope,
             :inserted_at,
             :updated_at,
             :deleted_at
           ]}
  schema "views" do
    field :slug, :string
    field :name, :string
    field :tag_filter, {:array, :string}, default: []
    field :description, :string
    field :scope, :string, default: "personal"
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :created_by, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(view, attrs) do
    view
    |> cast(attrs, [
      :workspace_id,
      :slug,
      :name,
      :tag_filter,
      :description,
      :scope,
      :created_by_id
    ])
    |> validate_required([:workspace_id, :slug, :name])
    |> common_validations()
    |> unique_constraint(:slug,
      name: :views_workspace_id_slug_active_index,
      message: "has already been taken"
    )
  end

  def update_changeset(view, attrs) do
    view
    |> cast(attrs, [:name, :tag_filter, :description, :scope])
    |> validate_required([:name])
    |> common_validations()
  end

  defp common_validations(changeset) do
    changeset
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:scope, @scopes)
    |> update_change(:slug, fn s -> if is_binary(s), do: String.downcase(s), else: s end)
    |> validate_slug()
    |> validate_tag_filter()
  end

  defp validate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        changeset

      slug ->
        case Slug.validate(slug) do
          :ok -> changeset
          {:error, _} -> add_error(changeset, :slug, "invalid slug format")
        end
    end
  end

  defp validate_tag_filter(changeset) do
    tags = get_field(changeset, :tag_filter) || []

    if Enum.any?(tags, fn t -> not is_binary(t) or Slug.validate(t) != :ok end) do
      add_error(changeset, :tag_filter, "tag_invalid")
    else
      put_change(changeset, :tag_filter, tags |> Enum.map(&String.downcase/1) |> Enum.uniq())
    end
  end
end
