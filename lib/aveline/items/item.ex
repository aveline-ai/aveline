defmodule Aveline.Items.Item do
  @moduledoc false
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Slug
  alias Aveline.Workspaces.Workspace

  @max_tags 16
  @max_title 200
  @valid_created_via ~w(cli web seed)

  @derive {Jason.Encoder,
           only: [
             :id,
             :slug,
             :title,
             :body,
             :summary,
             :tags,
             :pinned,
             :created_via,
             :inserted_at,
             :updated_at,
             :deleted_at
           ]}
  schema "items" do
    field :slug, :string
    field :title, :string
    field :body, :string, default: ""
    field :summary, :string
    field :tags, {:array, :string}, default: []
    field :pinned, :boolean, default: false
    field :created_via, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :owner, User, type: :binary_id
    belongs_to :created_by, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def max_tags, do: @max_tags

  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :workspace_id,
      :slug,
      :title,
      :body,
      :summary,
      :tags,
      :pinned,
      :owner_id,
      :created_by_id,
      :created_via
    ])
    |> validate_required([
      :workspace_id,
      :title,
      :owner_id,
      :created_by_id,
      :created_via
    ])
    |> maybe_derive_slug()
    |> common_validations()
    |> validate_inclusion(:created_via, @valid_created_via)
    |> unique_constraint(:slug,
      name: :items_workspace_id_slug_active_index,
      message: "has already been taken"
    )
  end

  def update_changeset(item, attrs) do
    item
    |> cast(attrs, [:title, :body, :summary, :tags, :pinned])
    |> common_validations()
  end

  defp common_validations(changeset) do
    changeset
    |> validate_length(:title, min: 1, max: @max_title)
    |> validate_slug()
    |> validate_tags()
  end

  defp maybe_derive_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        put_change(changeset, :slug, String.downcase(slug))

      _ ->
        case Slug.derive(get_field(changeset, :title)) do
          nil ->
            add_error(changeset, :slug, "could not derive slug from title")

          derived ->
            put_change(changeset, :slug, derived)
        end
    end
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

  defp validate_tags(changeset) do
    tags = get_field(changeset, :tags) || []

    cond do
      length(tags) > @max_tags ->
        add_error(changeset, :tags, "too many tags (max #{@max_tags})")

      Enum.any?(tags, fn t -> not is_binary(t) or Slug.validate(t) != :ok end) ->
        add_error(changeset, :tags, "tag_invalid")

      true ->
        # dedupe + lowercase
        normalized = tags |> Enum.map(&String.downcase/1) |> Enum.uniq()
        put_change(changeset, :tags, normalized)
    end
  end
end
