defmodule Aveline.Messages.ItemMessage do
  @moduledoc false
  use Aveline.Schema
  import Ecto.Changeset

  alias Aveline.Accounts.User
  alias Aveline.Items.Item

  @derive {Jason.Encoder,
           only: [
             :id,
             :item_id,
             :body,
             :created_via,
             :edited_at,
             :inserted_at,
             :updated_at,
             :deleted_at
           ]}
  schema "item_messages" do
    field :body, :string
    field :created_via, :string
    field :edited_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    belongs_to :item, Item, type: :binary_id
    belongs_to :author, User, type: :binary_id
    belongs_to :deleted_by, User, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(message, attrs) do
    message
    |> cast(attrs, [:item_id, :author_id, :body, :created_via])
    |> validate_required([:item_id, :author_id, :body, :created_via])
    |> validate_length(:body, min: 1, max: 10_000)
    |> validate_inclusion(:created_via, ~w(cli web agent seed))
  end

  def update_changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 10_000)
    |> put_change(:edited_at, DateTime.utc_now())
  end
end
