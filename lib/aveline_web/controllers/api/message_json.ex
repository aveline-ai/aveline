defmodule AvelineWeb.Api.MessageJSON do
  @moduledoc false

  alias AvelineWeb.Api.UserJSON

  def index(%{messages: messages}), do: %{messages: Enum.map(messages, &one/1)}
  def show(%{message: message}), do: one(message)

  def one(m) do
    %{
      id: m.id,
      item_id: m.item_id,
      block_id: m.block_id,
      body: m.body,
      actor: %{
        user: UserJSON.summary(loaded(m.actor_user)),
        type: m.actor_type
      },
      resolved_at: m.resolved_at,
      edited_at: m.edited_at,
      inserted_at: m.inserted_at,
      updated_at: m.updated_at,
      deleted_at: m.deleted_at
    }
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded(other), do: other
end
