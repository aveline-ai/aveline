defmodule Aveline.Comments.Comment do
  @moduledoc false
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Docs.Doc

  @actor_types ~w(human agent)

  @derive {Jason.Encoder,
           only: [
             :id,
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
    field :body, :string
    field :block_id, :string
    field :actor_type, :string
    field :resolved_at, :utc_datetime_usec
    field :edited_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    belongs_to :doc, Doc, type: :binary_id
    belongs_to :actor_user, User, type: :binary_id
    belongs_to :resolved_by, User, type: :binary_id
    belongs_to :resolved_by_doc, Doc, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id
    belongs_to :parent_comment, __MODULE__, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def actor_types, do: @actor_types

  def create_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:doc_id, :parent_comment_id, :block_id, :body, :actor_user_id, :actor_type])
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
