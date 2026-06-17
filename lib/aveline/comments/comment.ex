defmodule Aveline.Comments.Comment do
  @moduledoc """
  Comments mirror the docs versioning model. `base_comment_id` is the
  stable logical id of a thread node; `id` is the per-version row id.
  `parent_comment_id` references the parent's `base_comment_id` (no FK
  constraint — the column is non-unique across versions).

  The CURRENT row of a comment is the one with `deleted_at IS NULL` for
  a given `base_comment_id`. Edit = insert next version + supersede
  prior. Resolve / reanchor / delete update the current row in place.
  """
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Docs.Doc

  @actor_types ~w(human agent)

  @derive {Jason.Encoder,
           only: [
             :id,
             :base_comment_id,
             :version_number,
             :doc_id,
             :parent_comment_id,
             :block_id,
             :body,
             :actor_type,
             :resolved_at,
             :edited_at,
             :inserted_at,
             :updated_at,
             :deleted_at
           ]}
  schema "doc_comments" do
    field :base_comment_id, :binary_id
    field :version_number, :integer, default: 1

    field :body, :string
    field :block_id, :string
    field :actor_type, :string
    field :resolved_at, :utc_datetime_usec
    field :edited_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
    # parent_comment_id is a plain UUID (the parent's base_comment_id),
    # NOT a FK — multiple versions of the parent share that value.
    field :parent_comment_id, :binary_id

    belongs_to :doc, Doc, type: :binary_id
    belongs_to :actor_user, User, type: :binary_id
    belongs_to :resolved_by, User, type: :binary_id
    belongs_to :resolved_by_doc, Doc, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def actor_types, do: @actor_types

  def create_changeset(comment, attrs) do
    comment
    |> cast(attrs, [
      :base_comment_id,
      :version_number,
      :doc_id,
      :parent_comment_id,
      :block_id,
      :body,
      :actor_user_id,
      :actor_type,
      :resolved_at,
      :resolved_by_id,
      :resolved_by_doc_id,
      :edited_at
    ])
    |> validate_required([:doc_id, :body, :actor_user_id, :actor_type])
    |> validate_inclusion(:actor_type, @actor_types)
    |> validate_length(:body, min: 1, max: 10_000)
  end

  def update_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 10_000)
    |> put_change(:edited_at, DateTime.utc_now())
  end
end
