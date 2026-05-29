defmodule AvelineWeb.Api.MessageJSON do
  @moduledoc false

  alias AvelineWeb.Api.UserJSON

  def index(%{messages: messages}), do: %{messages: Enum.map(messages, &one/1)}
  def show(%{message: message}), do: one(message)

  def one(m) do
    %{
      id: m.id,
      item_id: m.item_id,
      body: m.body,
      author: UserJSON.summary(loaded(m.author)),
      created_via: m.created_via,
      edited_at: m.edited_at,
      inserted_at: m.inserted_at,
      updated_at: m.updated_at,
      deleted_at: m.deleted_at
    }
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded(other), do: other
end
