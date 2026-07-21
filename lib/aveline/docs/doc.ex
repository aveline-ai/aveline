defmodule Aveline.Docs.Doc do
  @moduledoc """
  A single VERSION of a block-structured doc.

  `base_doc_id` is the stable logical identifier shared across all versions;
  `id` is per-version. `deleted_at IS NULL` means this row is the current
  version of its base doc.
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Slug
  alias Aveline.Workspaces.Workspace

  @max_tags 16
  @max_title 200
  @max_summary 255
  @actor_types ~w(human agent)

  @derive {Jason.Encoder,
           only: [
             :id,
             :base_doc_id,
             :version_number,
             :slug,
             :title,
             :summary,
             :blocks,
             :tags,
             :pin_slot,
             :orientation,
             :visibility,
             :actor_type,
             :operations,
             :intent,
             :resolves_comment_ids,
             :comment_dispositions,
             :inserted_at,
             :updated_at,
             :deleted_at
           ]}
  schema "docs" do
    field :base_doc_id, :binary_id
    field :version_number, :integer
    field :slug, :string
    field :title, :string
    field :summary, :string
    field :blocks, {:array, :map}, default: []
    field :tags, {:array, :string}, default: []
    field :pin_slot, :integer
    # Exactly one per workspace; undeletable by CHECK. See Docs moduledoc.
    field :orientation, :boolean, default: false
    # private | workspace. Carried across versions like pin_slot;
    # changed in place on the current row (owner only). "Shared with
    # some people" is private plus doc_shares rows. Orientation docs
    # are forced workspace-visible by CHECK.
    field :visibility, :string, default: "workspace"
    field :actor_type, :string
    field :operations, {:array, :map}, default: []
    field :intent, :string
    field :resolves_comment_ids, {:array, :binary_id}, default: []
    # Each entry: %{"comment_id", "action" ("resolve"|"reanchor"|"leave"),
    #               "new_block_id"?, "note"?}. See Aveline.Comments.Disposition.
    field :comment_dispositions, {:array, :map}, default: []
    # Pre-flattened title + summary + tags + block text; populated in
    # Docs.apply_ops. The English tsvector is built from this column via
    # the docs_search_idx GIN index.
    field :search_text, :string, default: ""
    # ts_headline extract set by Docs.list_current when a search query is
    # present — why this doc matched, never persisted.
    field :search_snippet, :string, virtual: true
    # Mechanism vs intent (house model): superseded = a newer version
    # exists; deleted_at (+deleted_by) = a human deleted the doc.
    field :superseded, :boolean, default: false
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace, type: :binary_id
    belongs_to :owner, User, type: :binary_id
    belongs_to :actor_user, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def max_tags, do: @max_tags
  def actor_types, do: @actor_types

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [
      :base_doc_id,
      :version_number,
      :workspace_id,
      :slug,
      :title,
      :summary,
      :blocks,
      :tags,
      :pin_slot,
      :orientation,
      :visibility,
      :owner_id,
      :actor_user_id,
      :actor_type,
      :operations,
      :intent,
      :resolves_comment_ids,
      :comment_dispositions,
      :search_text
    ])
    |> validate_required([
      :base_doc_id,
      :version_number,
      :workspace_id,
      :slug,
      :title,
      :owner_id,
      :actor_user_id,
      :actor_type
    ])
    |> validate_inclusion(:actor_type, @actor_types)
    |> validate_inclusion(:visibility, ~w(private workspace))
    |> validate_length(:title, min: 1, max: @max_title)
    |> validate_length(:summary, max: @max_summary)
    |> validate_slug()
    |> validate_tags()
    |> unique_constraint(:slug,
      name: :docs_workspace_id_slug_active_index,
      message: "has already been taken"
    )
    |> unique_constraint([:base_doc_id, :version_number])
    |> unique_constraint(:orientation,
      name: :docs_one_orientation_per_workspace_idx,
      message: "workspace already has an orientation doc"
    )
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

      Enum.any?(tags, fn t -> not is_binary(t) or not valid_tag_slug?(t) end) ->
        add_error(changeset, :tags, "tag_invalid")

      true ->
        normalized = tags |> Enum.map(&String.downcase/1) |> Enum.uniq()
        put_change(changeset, :tags, normalized)
    end
  end

  # Plain slug or scoped `scope:value` — mirrors Tag.validate_slug_format.
  defp valid_tag_slug?(slug) do
    case String.split(slug, ":") do
      [plain] -> Slug.validate(plain) == :ok
      [scope, value] -> Slug.validate(scope) == :ok and Slug.validate(value) == :ok
      _ -> false
    end
  end
end
