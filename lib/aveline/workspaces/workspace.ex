defmodule Aveline.Workspaces.Workspace do
  @moduledoc false
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Slug

  @derive {Jason.Encoder, only: [:id, :slug, :name, :template, :inserted_at, :updated_at, :deleted_at]}
  schema "workspaces" do
    field :slug, :string
    field :name, :string
    # The template this workspace was created from (Aveline.Workspaces.Template).
    # Nil for workspaces that predate templates.
    field :template, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :created_by, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:slug, :name, :created_by_id, :template])
    |> validate_required([:slug, :name, :created_by_id, :template])
    |> validate_inclusion(:template, Aveline.Workspaces.Template.names(), message: "unknown template")
    |> validate_length(:name, min: 1, max: 200)
    |> update_change(:slug, &normalize_slug/1)
    |> validate_format(:slug, Slug.regex(), message: "invalid slug format")
    |> validate_length(:slug, min: 1, max: Slug.max_length())
    |> unique_constraint(:slug)
  end

  def update_changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end

  defp normalize_slug(nil), do: nil
  defp normalize_slug(slug) when is_binary(slug), do: String.downcase(slug)
end
